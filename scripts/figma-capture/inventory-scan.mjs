// Counts, across every rendered scene in build/figma-capture, where each lib
// widget and each Material control paints, how often, and in which visual
// variants. inventory.mjs groups the counts into design components.
import fs from 'node:fs';
import path from 'node:path';
import { AREAS, OUT, PAGES, REPO } from './areas.mjs';
import { intersects, leaf, union } from './simplify.mjs';
import { themeTokens } from './tokens.mjs';

const TOKENS = Object.entries(themeTokens().colors).map(([name, c]) => ({
  // Avatar hues are picked per person, so they count as one colour.
  name: name.startsWith('avatar/') ? 'avatar' : name.split('/').pop(),
  rgb: [c.r, c.g, c.b],
}));

/** The theme token a painted colour comes from, with its opacity: "onSurface@60". */
function colorName(c) {
  if (!c) return '';
  const hit = TOKENS.find((t) => t.rgb.every((v, i) => Math.abs(v - c[i]) < 0.006));
  const alpha = Math.round(c[3] * 100);
  return `${hit?.name ?? 'raw'}${alpha === 100 ? '' : `@${alpha}`}`;
}

/** What a leaf looks like regardless of its text and position. */
function look(l) {
  switch (l.k) {
    case 'text': return `text ${[...new Set(l.runs.map((r) => `${r.size}/${r.weight} ${colorName(r.color)}`))].join(',')}`;
    case 'icon': return `icon ${l.name} ${colorName(l.color)}`;
    case 'image': case 'shadow': case 'backdrop': return l.k;
    default: return `${l.k} ${l.gradient ? 'gradient' : colorName(l.fill)} ${colorName(l.stroke)}`.trim();
  }
}

const clipTo = (r, c) => {
  const x = Math.max(r.x, c.x), y = Math.max(r.y, c.y);
  return { x, y, w: Math.min(r.x + r.w, c.x + c.w) - x, h: Math.min(r.y + r.h, c.y + c.h) - y };
};
const grow = (r, by) => (r ? union([r, by]) : { ...by });

/** Files (by stem) under lib/ declaring each widget class, matched as the recorder matches them. */
const DECLARED = new Map();
for (const file of fs.readdirSync(path.join(REPO, 'lib'), { recursive: true })) {
  if (!file.endsWith('.dart')) continue;
  const src = fs.readFileSync(path.join(REPO, 'lib', file), 'utf8');
  for (const [, name] of src.matchAll(/^class (\w+)(?:<[^{]*?>)? extends \w*(?:Stateless|Stateful|Consumer|Animated)\w*Widget\b/gm)) {
    DECLARED.set(name, [...(DECLARED.get(name) ?? []), path.basename(file, '.dart')]);
  }
}

/** A widget's key and file. Private names repeat across files, so they carry their file: "media_viewer._MediaCaption". */
function identify(name, chain) {
  const files = DECLARED.get(name) ?? [];
  if (!files.length) throw new Error(`${name}: no widget class of that name under lib/`);
  if (!name.startsWith('_')) return { key: name, file: files[0] };
  const file = files.length > 1 ? files.find((f) => chain.some((i) => i.file === f)) : files[0];
  if (!file) throw new Error(`${name}: declared in ${files.join(', ')}, none of them above it`);
  return { key: `${file}.${name}`, file };
}

/**
 * Painted instances in one scene: { key, type, state?, rect, looks, kids, parent }, where
 * parent is the key of the nearest enclosing widget that paints itself.
 * [wrappers] add behaviour only: what they paint counts toward the widget
 * around them, and the ones met are added to [met].
 */
export function sceneInstances(scene, wrappers, met) {
  const byId = new Map();
  const open = (id, make) => byId.get(id) ?? byId.set(id, make()).get(id);
  const screen = { x: 0, y: 0, w: scene.w, h: scene.h };
  function visit(node, clip, chain, lib, control) {
    if (node.t !== 'g' && node.t !== 'clip' && node.t !== 'root') {
      const l = leaf(node);
      if (!l?.r || !intersects(l.r, clip)) return;
      const seen = clipTo(l.r, clip);
      for (const i of chain) i.rect = grow(i.rect, seen);
      lib?.looks.add(look(l));
      return;
    }
    const id = node.lib && node.libId !== lib?.libId ? identify(node.lib, chain) : null;
    if (id && wrappers.has(id.key)) met.add(id.key);
    else if (id) {
      const parent = lib;
      lib = open(`l${node.libId}`, () => ({ ...id, type: 'lib', libId: node.libId, looks: new Set(), kids: new Set(), up: parent }));
      parent?.kids.add(id.key);
      chain = [...chain, lib];
    }
    if (node.control && node.controlId !== control?.controlId) {
      control = open(`c${node.controlId}`, () => ({ key: node.control, type: 'control', controlId: node.controlId, state: node.controlState ?? 'default', up: lib }));
      lib?.kids.add(`${node.control}:${control.state}`);
      chain = [...chain, control];
    }
    const inner = node.t === 'clip' && node.r ? clipTo(node.r, clip) : clip;
    for (const c of node.c ?? []) if (typeof c === 'object') visit(c, inner, chain, lib, control);
  }
  visit(scene.tree, screen, [], null, null);
  // A parent is the nearest enclosing widget that paints something itself.
  for (const i of byId.values()) {
    let p = i.up;
    while (p && !p.looks.size) p = p.up;
    i.parent = p?.key;
  }
  return [...byId.values()].filter((i) => i.rect);
}

/** A lib instance's variant: what it paints itself plus what it is built from. */
const variantOf = (i) => (i.type === 'control' ? i.state : [...i.looks, ...[...i.kids].map((k) => `+${k}`)].sort().join(' | '));

/** Every rendered scene.json with { id, title, area, form, dir, w, h } about it, in canvas order. */
function* renderedScenes() {
  for (const { area } of AREAS) for (const form of Object.keys(PAGES)) {
    const dir = path.join(OUT, area, form);
    const scenes = fs.existsSync(dir) ? fs.readdirSync(dir).sort() : [];
    for (const d of scenes.filter((s) => fs.existsSync(path.join(dir, s, 'scene.json')))) {
      const scene = JSON.parse(fs.readFileSync(path.join(dir, d, 'scene.json'), 'utf8'));
      yield { scene, info: { id: scene.id, title: scene.title, area, form, dir: path.join(dir, d), w: scene.w, h: scene.h } };
    }
  }
}

/** Rendered scenes, widget key → stats, and the [wrappers] met. */
export function scan(wrappers) {
  const scenes = [], widgets = new Map(), wrapped = new Set();
  for (const { scene, info } of renderedScenes()) {
    scenes.push(info);
    for (const i of sceneInstances(scene, wrappers, wrapped)) record(widgets, i, info);
  }
  return { scenes, widgets, wrapped };
}

function record(widgets, i, scene) {
  const w = widgets.get(i.key) ?? widgets.set(i.key, { key: i.key, type: i.type, painted: new Set(), instances: 0, parents: new Map(), variants: new Map() }).get(i.key);
  // Only what the instance paints itself tells its look; an empty one adds nothing.
  if (i.type !== 'control' && !i.looks.size) return;
  w.instances++;
  w.painted.add(scene.id);
  w.parents.set(i.parent, (w.parents.get(i.parent) ?? 0) + 1);
  const v = variantOf(i);
  const variant = w.variants.get(v) ?? w.variants.set(v, { signature: v, count: 0, examples: [] }).get(v);
  variant.count++;
  if (variant.examples.length < 3 && !variant.examples.some((e) => e.scene.id === scene.id)) variant.examples.push({ scene, rect: i.rect });
}
