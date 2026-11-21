// Builds one recorded scene (scene.json + images) as editable layers in Figma.
import fs from 'node:fs';
import path from 'node:path';
import { execute } from './mcp.mjs';
import { simplify } from './simplify.mjs';

const runtime = fs.readFileSync(new URL('./runtime.js', import.meta.url), 'utf8');

/** Places the scene in [section] on [page], at grid [slot]; returns the frame id. */
export async function build(dir, { page, section, sectionIndex, slot, cols }) {
  const scene = JSON.parse(fs.readFileSync(path.join(dir, 'scene.json'), 'utf8'));
  const tree = simplify(scene);
  const used = new Set();
  (function collect(n) { if (n.k === 'image') used.add(n.img); for (const k of n.kids ?? []) collect(k); })(tree);
  const images = Object.fromEntries([...used].map((k) => [k, fs.readFileSync(path.join(dir, `${k}.png`)).toString('base64')]));
  const D = { id: scene.id, title: scene.title, page, section, sectionIndex, slot, cols, tree, images };
  return execute(`const D = ${JSON.stringify(D)};\n${runtime}`);
}
