// Captures the shipping Flutter UI into the Figma file open with the
// figma-console Desktop Bridge plugin, as editable layers.
//
//   node scripts/figma-capture/capture.mjs [area ...] [--device desktop|mobile]
//        [--publish-only] [--verify]
//
// For each area (all by default) and form factor it renders the scenes in
// scenarios/<area>_test.dart with the real widgets and fictional data,
// rebuilds every scene in the area's Figma section and drops frames of
// scenes that no longer exist.
// --publish-only reuses the last render in build/figma-capture/.
// --verify then compares each Figma frame with its Flutter render.
// Needs: flutter on PATH, `npm ci` in this directory, Figma desktop with the
// Desktop Bridge plugin running in the target file.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { AREAS, OUT, PAGES, REPO } from './areas.mjs';
import { build } from './build.mjs';
import { execute } from './mcp.mjs';
import { ensureTokens } from './tokens.mjs';
import { verify } from './verify.mjs';

const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const device = args.includes('--device') ? args[args.indexOf('--device') + 1] : null;
const wanted = args.filter((a, i) => !a.startsWith('--') && args[i - 1] !== '--device');
const areas = wanted.length ? AREAS.filter((a) => wanted.includes(a.area)) : AREAS;
const devices = device ? [device] : Object.keys(PAGES);
if (areas.length !== (wanted.length || AREAS.length)) throw new Error(`Unknown area in: ${wanted.join(' ')}`);

// moshThemeData is built once per isolate, so each form factor renders in its own run.
function render(area, form) {
  const test = `scripts/figma-capture/scenarios/${area}_test.dart`;
  const run = spawnSync('flutter', ['test', test, '--dart-define=SETUP_PREVIEW=true', `--dart-define=FIGMA_DEVICE=${form}`],
    { cwd: REPO, stdio: 'inherit', shell: process.platform === 'win32' });
  if (run.status !== 0) throw new Error(`${area} ${form}: flutter test failed`);
}

// Removes the section's frames whose scene is not in [keep]: scenes that no longer exist.
const pruneSection = (page, section, keep) => execute(`
  await figma.loadAllPagesAsync();
  const page = figma.root.children.find((p) => p.name === ${JSON.stringify(page)});
  const keep = new Set(${JSON.stringify(keep)});
  for (const s of page ? page.children : []) {
    if (s.type !== 'SECTION' || s.getPluginData('section') !== ${JSON.stringify(section)}) continue;
    for (const f of [...s.children]) if (!keep.has(f.getPluginData('sceneId'))) f.remove();
  }`);

await ensureTokens();
const built = [];
for (const [sectionIndex, { area, section }] of AREAS.entries()) {
  if (!areas.some((a) => a.area === area)) continue;
  for (const form of devices) {
    const dir = path.join(OUT, area, form);
    if (!flag('--publish-only')) {
      fs.rmSync(dir, { recursive: true, force: true });
      render(area, form);
    }
    const { page, cols } = PAGES[form];
    const scenes = fs.existsSync(dir) ? fs.readdirSync(dir).filter((d) => fs.existsSync(path.join(dir, d, 'scene.json'))).sort() : [];
    if (!scenes.length) throw new Error(`${area} ${form}: nothing rendered in ${dir}`);
    // Frames are replaced scene by scene, so a failed run leaves the previous ones in place.
    const keep = [];
    for (const [slot, scene] of scenes.entries()) {
      const { id, sceneId } = await build(path.join(dir, scene), { page, section, sectionIndex, slot, cols });
      keep.push(sceneId);
      built.push({ id, ref: path.join(dir, scene, 'ref.png'), name: `${area} ${form} ${scene}` });
    }
    await pruneSection(page, section, keep);
    console.log(`${area} ${form}: ${scenes.length} frames`);
  }
}
if (flag('--verify')) await verify(built);
