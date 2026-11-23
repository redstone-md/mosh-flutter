// Builds the redesign's reference screens in the Figma file "Mosh": the
// "Screens" section on the Redesign page, out of the components build.mjs made,
// then checks them (audit.js). Needs the Desktop Bridge plugin open in the file.
//
//   node screens.mjs               every screen
//   node screens.mjs chats call    the screens of these scripts in screens/
//   node screens.mjs --audit       only the check
//
// A screen that is built again keeps its frame and node id; only what is in it is new.
// So a script that throws leaves its screens empty or half filled: run it again once it is mended.
import { check, guarded, parse, run } from './run.mjs';

// In the order their columns stand in the section.
const SCREENS = ['chats', 'group', 'start', 'setup', 'settings', 'call', 'dialog', 'media'];
const { names, audit } = parse(process.argv.slice(2), SCREENS);
const built = [];
for (const SCREEN_SCRIPT of audit ? [] : SCREENS.filter((s) => !names.length || names.includes(s))) {
  const started = Date.now();
  const frames = await run(guarded(`screens/${SCREEN_SCRIPT}.js`, 'done'), { SCREENS, SCREEN_SCRIPT }, ['screens.js']);
  console.log(`${SCREEN_SCRIPT}: ${frames.join(', ')}; ${((Date.now() - started) / 1000).toFixed(1)} s`);
  built.push(...frames);
}
await check('Screens', names.length ? built : null);
