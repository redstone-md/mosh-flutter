// Turns a recorded paint tree (scene.json) into a compact layer tree with
// global coordinates: frames where Flutter has a visible box, clip or a
// named lib widget, leaves for shapes, text, icons, paths and images.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import opentype from 'opentype.js';
import { REPO } from './areas.mjs';
import { windowColor } from './tokens.mjs';

// Icons are glyphs of a font; their outlines become vectors. The app's icons
// come from the Phosphor fonts in assets/fonts (MoshIcons), the ones Material
// draws on its own (checkbox, expansion chevron) from Flutter's bundled font.
const flutterBin = fs.realpathSync(execFileSync(process.platform === 'win32' ? 'where' : 'which', ['flutter'], { encoding: 'utf8' }).split(/\r?\n/)[0]);
const FONTS = path.join(path.dirname(flutterBin), 'cache', 'artifacts', 'material_fonts');
const phosphor = (file) => opentype.loadSync(path.join(REPO, 'assets', 'fonts', file));
const ICON_FONTS = {
  MaterialIcons: opentype.loadSync(path.join(FONTS, 'MaterialIcons-Regular.otf')),
  Phosphor: phosphor('Phosphor.ttf'), PhosphorFill: phosphor('Phosphor-Fill.ttf'), PhosphorBold: phosphor('Phosphor-Bold.ttf'),
};
/** "family:codepoint" → the MoshIcons role that draws it (the first, when two roles share a glyph). */
const ROLES = new Map();
for (const [, role, hex, family] of fs.readFileSync(path.join(REPO, 'lib', 'src', 'app', 'mosh_icons.dart'), 'utf8')
  .matchAll(/static const IconData (\w+) =\s*IconData\(0x([0-9a-f]+), fontFamily: '(\w+)'\)/g)) {
  const key = `${family}:${parseInt(hex, 16)}`;
  if (!ROLES.has(key)) ROLES.set(key, role);
}
const ICON_NAMES = new Map();
for (const line of fs.readFileSync(path.join(FONTS, 'codepoints'), 'utf8').split('\n')) {
  const [name, hex] = line.trim().split(' ');
  if (!name || !hex) continue;
  const cp = parseInt(hex, 16), prev = ICON_NAMES.get(cp);
  // Prefer the plain name over _baseline/_outlined/... aliases of the same glyph.
  if (!prev || (/_(baseline|outlined|rounded|sharp)$/.test(prev) && !/_(baseline|outlined|rounded|sharp)$/.test(name))) ICON_NAMES.set(cp, name);
}

const near = (a, b, tol = 0.75) => Math.abs(a - b) <= tol;
const sameRect = (a, b, tol = 0.75) => a && b && near(a.x, b.x, tol) && near(a.y, b.y, tol) && near(a.w, b.w, tol) && near(a.h, b.h, tol);
const inside = (a, b) => a.x >= b.x - 0.5 && a.y >= b.y - 0.5 && a.x + a.w <= b.x + b.w + 0.5 && a.y + a.h <= b.y + b.h + 0.5;
export const intersects = (a, b) => a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
export const union = (rs) => {
  const x = Math.min(...rs.map((r) => r.x)), y = Math.min(...rs.map((r) => r.y));
  return { x, y, w: Math.max(...rs.map((r) => r.x + r.w)) - x, h: Math.max(...rs.map((r) => r.y + r.h)) - y };
};
const visible = (c) => c && c[3] > 0.004;

function iconNode(op) {
  const run = op.runs[0];
  const cp = op.text.codePointAt(0);
  const size = run.size;
  const font = ICON_FONTS[run.family];
  const glyph = font.charToGlyph(String.fromCodePoint(cp));
  const upm = font.unitsPerEm, asc = font.ascender, desc = -font.descender;
  // An app icon goes by its MoshIcons role; Material's names come from the codepoints file.
  const name = ROLES.get(`${run.family}:${cp}`) ?? ((run.family === 'MaterialIcons' && ICON_NAMES.get(cp)) || `icon-${cp.toString(16)}`).replace(/_baseline$/, '');
  // Icon paints with height 1.0 and even leading: the em box is centred in the line.
  const baseline = (size - (size * (asc + desc)) / upm) / 2 + (size * asc) / upm;
  const d = glyph.getPath(0, baseline, size).toPathData(2);
  // A rotated icon (expanded ExpansionTile chevron) keeps its unrotated box;
  // the rotation is applied around the box centre.
  return { k: 'icon', name, r: { ...op.r, w: Math.max(op.r.w, size), h: Math.max(op.r.h, size) }, size, d, rot: op.rot, color: run.color };
}

export function leaf(op) {
  switch (op.t) {
    case 'text': {
      if (!op.text.trim() || !op.runs.length) return null;
      if (op.runs[0].family in ICON_FONTS) return visible(op.runs[0].color) ? iconNode(op) : null;
      let text = op.text, runs = op.runs;
      // Insert a line separator at each mid-word break, shifting later runs.
      for (const at of (op.lines > 1 ? (op.breaks ?? []).slice(0, op.lines - 1) : []).reverse()) {
        text = text.slice(0, at) + '\u2028' + text.slice(at);
        runs = runs.map((r) => ({ ...r, s: r.s >= at ? r.s + 1 : r.s, e: r.e >= at ? r.e + 1 : r.e }));
      }
      return { k: 'text', r: op.r, text: text.replace(/\uFFFC/g, ' '), runs, lines: op.lines, align: op.align, ellipsis: op.ellipsis, editable: op.editable };
    }
    case 'rect': case 'ellipse':
      if (!visible(op.fill) && !visible(op.stroke) && !op.gradient) return null;
      if (op.r.w < 0.3 && op.r.h < 0.3) return null;
      return { k: op.t, ...op };
    case 'path':
      if (!visible(op.fill) && !visible(op.stroke)) return null;
      return { k: 'path', ...op };
    case 'image': return { k: 'image', ...op };
    case 'backdrop': return { k: 'backdrop', ...op };
    case 'shadow': return { k: 'shadow', ...op };
    default: return null;
  }
}

/** Returns a list of layer nodes for [node] (lifted when the scope adds nothing). */
function walk(node, ctx) {
  if (node.t !== 'g' && node.t !== 'clip' && node.t !== 'root') {
    const l = leaf(node);
    return l && l.r && intersects(l.r, ctx.clip) ? [l] : [];
  }
  const clip = node.t === 'clip' && node.r ? node.r : ctx.clip;
  const libId = node.libId ?? ctx.libId;
  let kids = [];
  for (const c of node.c ?? []) kids.push(...walk(c, { clip, libId }));
  kids = attachShadows(kids);
  if (!kids.length) return [];
  const own = node.r && node.r.w < 50000 ? node.r : null;

  if (node.t === 'clip') {
    const needed = kids.some((k) => !inside(k.r, node.r));
    // A rounded clip still matters when a filled layer reaches into a corner.
    const rad = node.clip?.radius ?? 0, c = node.r;
    const cornered = rad > 0 && kids.some((k) => k.k !== 'text' && k.k !== 'icon' &&
      ((k.r.x < c.x + rad / 2 || k.r.x + k.r.w > c.x + c.w - rad / 2) && (k.r.y < c.y + rad / 2 || k.r.y + k.r.h > c.y + c.h - rad / 2)));
    if (!needed && !cornered) return kids;
    return [{ k: 'frame', name: 'clip', r: node.r, clip: true, radius: node.clip?.radius ?? 0, kids }];
  }
  if (node.t === 'root') return kids;

  const frame = { k: 'frame', name: node.lib && node.libId !== ctx.libId ? node.lib : node.name, r: own ?? union(kids.map((k) => k.r)), kids };
  mergeBox(frame);
  // A lone clip frame with our bounds folds into us.
  if (frame.kids.length === 1 && frame.kids[0].k === 'frame' && frame.kids[0].clip && sameRect(frame.kids[0].r, frame.r)) {
    const c = frame.kids[0];
    frame.clip = true; frame.radius = frame.radius ?? c.radius; frame.kids = c.kids;
  }
  const styled = frame.fill || frame.stroke || frame.clip || frame.gradient || frame.effects;
  const named = node.lib && node.libId !== ctx.libId && countLeaves(frame) >= 2;
  if (!styled && !named) return frame.kids;
  if (!styled && frame.kids.length === 1 && frame.kids[0].k === 'frame') {
    frame.kids[0].name = frame.name; return frame.kids;
  }
  return [frame];
}

function countLeaves(n) { return n.kids ? n.kids.reduce((s, k) => s + countLeaves(k), 0) : 1; }

// Background and border shapes that exactly cover the frame become its fill and stroke.
function mergeBox(frame) {
  const first = frame.kids[0];
  if (first && (first.k === 'rect' || first.k === 'ellipse') && sameRect(first.r, frame.r) && !first.blur && (first.fill || first.gradient)) {
    frame.fill = first.fill; frame.gradient = first.gradient; frame.radius = first.radius; frame.radii = first.radii;
    frame.ellipse = first.k === 'ellipse'; frame.effects = first.effects;
    if (first.stroke) { frame.stroke = first.stroke; frame.sw = first.sw; frame.inside = first.inside; }
    frame.kids = frame.kids.slice(1);
  }
  const i = frame.kids.findIndex((k) => (k.k === 'rect' || k.k === 'ellipse') && k.stroke && !k.fill &&
    (sameRect(k.r, frame.r) || sameRect(k.r, { x: frame.r.x + k.sw / 2, y: frame.r.y + k.sw / 2, w: frame.r.w - k.sw, h: frame.r.h - k.sw })));
  // Only a border painted before the content can become the frame's stroke;
  // one painted over the children stays a layer above them.
  if (i === 0 && !frame.stroke) {
    const k = frame.kids[i];
    frame.stroke = k.stroke; frame.sw = k.sw; frame.inside = true; frame.radius ??= k.radius; frame.ellipse ||= k.k === 'ellipse';
    frame.kids = frame.kids.filter((_, j) => j !== i);
  }
}

// A Material elevation shadow becomes a drop shadow on the shape painted right after it.
function attachShadows(kids) {
  const out = [];
  for (let i = 0; i < kids.length; i++) {
    const k = kids[i];
    if (k.k !== 'shadow') { out.push(k); continue; }
    const next = kids[i + 1];
    if (next && sameRect(next.r, k.r, 2)) {
      next.effects = [{ type: 'DROP_SHADOW', color: k.color, offset: { x: 0, y: k.elevation * 0.5 }, radius: k.elevation * 1.5 }];
    }
  }
  return out;
}

export function simplify(scene) {
  const screen = { x: 0, y: 0, w: scene.w, h: scene.h };
  const kids = walk(scene.tree, { clip: screen, libId: null });
  // The window paints its colour beneath the app; translucent layers need it.
  return { k: 'frame', name: scene.title, r: screen, clip: true, fill: [...windowColor(), 1], kids };
}
