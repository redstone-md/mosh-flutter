// Builds the design component inventory from the last capture render
// (build/figma-capture, written by capture.mjs or its scenario tests):
//
//   node scripts/figma-capture/inventory.mjs [--widgets] [--figma]
//
// Groups the widgets that paint into the components of components.mjs and
// writes build/figma-capture/inventory.md: per component the widgets it
// covers, the frames and instances they paint, their states in the capture
// and up to three example frames. Fails when a widget that paints in more than
// one scene is not classified, or components.mjs names a widget that no
// longer paints.
// The report ends with every widget that paints: its owner, counts and areas.
// --widgets also prints every captured widget to stdout, before the check.
// --figma links the examples to their frames and publishes the
// "Components inventory" section on the Redesign page.
import fs from 'node:fs';
import path from 'node:path';
import { OUT } from './areas.mjs';
import { COMPONENTS, GROUPS, SCREEN_GROUP, SCREEN_PARTS, WRAPPERS } from './components.mjs';
import { frameIds, publishInventory } from './inventory-figma.mjs';
import { scan } from './inventory-scan.mjs';
import { union } from './simplify.mjs';

const args = process.argv.slice(2);
const { scenes, widgets, wrapped } = scan(new Set(WRAPPERS));
if (!scenes.length) throw new Error(`nothing rendered in ${OUT}`);

const LISTS = [...COMPONENTS.map((c) => [c.name, c.widgets]), [SCREEN_GROUP.title, SCREEN_PARTS]];
/** Widget key → its component's name, or the screen parts' title. */
const OWNER = new Map(LISTS.flatMap(([name, keys]) => keys.map((key) => [key, name])));

/** Throws when components.mjs disagrees with the capture. */
function check() {
  const problems = [], seen = new Map();
  for (const [name, keys] of LISTS) {
    for (const key of keys) {
      if (seen.has(key)) problems.push(`${key}: listed under ${seen.get(key)} and ${name}`);
      seen.set(key, name);
      if (!widgets.get(key)?.painted.size) problems.push(`${key} (${name}): does not paint in the capture`);
    }
  }
  for (const key of WRAPPERS) if (!wrapped.has(key)) problems.push(`${key} (wrapper): not in the capture`);
  for (const w of widgets.values()) {
    if (w.painted.size > 1 && !OWNER.has(w.key)) problems.push(`${w.key}: paints in ${w.painted.size} scenes but is not classified`);
  }
  if (problems.length) throw new Error(`components.mjs is out of date:\n  ${problems.join('\n  ')}`);
}

const short = (title) => title.split(' / ').slice(1).join(' / ');

/** Up to 3 examples that together show the most variants, one on the phone when it appears there. */
function examples(ws) {
  const variants = ws.flatMap((w) => [...w.variants.values()].map((v) => ({ ...v, widget: w.key })));
  const covers = new Map();
  for (const v of variants) for (const e of v.examples) {
    const c = covers.get(e.scene.id) ?? covers.set(e.scene.id, { scene: e.scene, rect: e.rect, variants: new Set() }).get(e.scene.id);
    // The crop spans every variant the scene is picked for.
    c.rect = union([c.rect, e.rect]);
    c.variants.add(`${v.widget} ${v.signature}`);
  }
  const picked = [], seen = new Set();
  const gain = (c) => [...c.variants].filter((v) => !seen.has(v)).length;
  for (let n = 0; n < 3 && covers.size; n++) {
    const pool = [...covers.values()].filter((c) => !picked.includes(c));
    const needPhone = n === 2 && !picked.some((c) => c.scene.form === 'mobile');
    const best = (needPhone && pool.some((c) => c.scene.form === 'mobile') ? pool.filter((c) => c.scene.form === 'mobile') : pool)
      .sort((a, b) => gain(b) - gain(a) || (a.scene.form === 'desktop' ? -1 : 1))[0];
    if (!best || (n > 0 && !gain(best) && !needPhone)) break;
    picked.push(best);
    best.variants.forEach((v) => seen.add(v));
  }
  return picked;
}

const MAX_LOOKS = 6;

/**
 * States a widget shows in the capture: a control's states, or a lib widget's
 * looks, each told by how it differs from the most common one and where it
 * first appears: «Thread» ×46 +FailedMessageRetry, text 13.5/400 onSurface.
 */
function states(w) {
  const vs = [...w.variants.values()].sort((a, b) => b.count - a.count);
  if (w.type === 'control') return `${w.key}: ${vs.map((v) => `${v.signature} ×${v.count}`).join(', ')}`;
  const base = vs[0].signature.split(' | ');
  const told = vs.slice(0, MAX_LOOKS).map((v, i) => {
    const t = v.signature.split(' | ');
    const diff = [...t.filter((x) => !base.includes(x)), ...base.filter((x) => !t.includes(x)).map((x) => `no ${x}`)];
    return `«${short(v.examples[0].scene.title)}» ×${v.count}${i ? ` ${diff.join(', ')}` : ''}`;
  });
  const more = vs.length > MAX_LOOKS ? `, ${vs.length - MAX_LOOKS} more` : '';
  return `${w.key} (${vs.length} ${vs.length === 1 ? 'look' : 'looks'}): ${told.join('; ')}${more}`;
}

function summarize(c) {
  const ws = c.widgets.map((k) => widgets.get(k));
  return {
    ...c,
    frames: new Set(ws.flatMap((w) => [...w.painted])).size,
    // Parts nested in another widget of the component are the same instance.
    instances: ws.reduce((s, w) => s + [...w.parents].reduce((n, [parent, count]) => n + (c.widgets.includes(parent) ? 0 : count), 0), 0),
    states: ws.map(states),
    examples: examples(ws),
  };
}

/** Frames a widget paints in, per capture area: "chats 12, conversation 40". */
const areas = (w) => Object.entries(Object.groupBy([...w.painted], (id) => id.split('.')[0])).map(([a, ids]) => `${a} ${ids.length}`).join(', ');

function markdown(components, url) {
  const link = (e) => (url ? `[${short(e.scene.title)} · ${e.scene.form}](${url(e.scene.id)})` : `${short(e.scene.title)} · ${e.scene.form}`);
  const out = [];
  for (const g of GROUPS) {
    out.push(`### ${g.title} (${g.ticket})`, '', '| Component | Widgets and their states in the capture | Frames | Instances | Examples |', '|---|---|---|---|---|');
    for (const c of components.filter((x) => x.group === g.id)) {
      out.push(`| ${c.name} | ${c.states.join('; ')} | ${c.frames} | ${c.instances} | ${c.examples.map(link).join('; ')} |`);
    }
    out.push('');
  }
  out.push(`### ${SCREEN_GROUP.title} (${SCREEN_GROUP.ticket})`, '', SCREEN_PARTS.join(', '), '');
  out.push('### Wrappers', '', 'What they wrap paints as the widget around them.', '', WRAPPERS.join(', '), '');
  const painting = [...widgets.values()].filter((w) => w.painted.size).sort((a, b) => b.painted.size - a.painted.size);
  out.push('### Widgets', '', '| Widget | Owner | Frames | Instances | Areas |', '|---|---|---|---|---|');
  for (const w of painting) out.push(`| ${w.key} | ${OWNER.get(w.key) ?? 'one scene, unclassified'} | ${w.painted.size} | ${w.instances} | ${areas(w)} |`);
  return out.join('\n');
}

function printWidgets() {
  const rows = [...widgets.values()].sort((a, b) => b.painted.size - a.painted.size);
  for (const w of rows) {
    const parent = [...w.parents.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? '';
    console.log([w.painted.size, w.instances, w.variants.size, w.type, w.key, `in ${parent}`, OWNER.get(w.key) ?? ''].join('\t'));
  }
}

if (args.includes('--widgets')) printWidgets();
check();
const components = COMPONENTS.map(summarize);
const ids = args.includes('--figma') ? await frameIds(scenes) : null;
if (ids) await publishInventory({ components, ids });
const md = markdown(components, ids?.url);
fs.writeFileSync(path.join(OUT, 'inventory.md'), md);
console.log(`${components.length} components over ${scenes.length} frames → ${path.join(OUT, 'inventory.md')}`);
