// Builds the redesign's reference screens in the Figma file "Mosh": the
// "Screens" section on the Redesign page, out of the components build.mjs made,
// then checks them (audit.js). Needs the Desktop Bridge plugin open in the file.
//
//   node screens.mjs               every screen
//   node screens.mjs chats call    the screens of these scripts in screens/
//   node screens.mjs --audit       only the check
//
// A screen that is built again keeps its frame and node id; only what is in it is new.
import { read, run } from './run.mjs';

// In the order their columns stand in the section.
const SCREENS = ['chats', 'group', 'start', 'setup', 'settings', 'call', 'dialog', 'media'];
const args = process.argv.slice(2), names = args.filter((a) => !a.startsWith('--'));
const unknown = names.filter((n) => !SCREENS.includes(n));
// A mistyped flag must not fall through to a build of every screen.
if (unknown.length || args.some((a) => a.startsWith('--') && a !== '--audit') || (args.includes('--audit') && args.length > 1)) throw new Error(`cannot read "${args.join(' ')}"; screens: ${SCREENS.join(', ')}`);

let built = null;
if (!args.includes('--audit')) {
  built = [];
  for (const SCREEN_SCRIPT of names.length ? SCREENS.filter((s) => names.includes(s)) : SCREENS) {
    const started = Date.now();
    const script = `try {\n${read(`screens/${SCREEN_SCRIPT}.js`)}\nreturn await done();\n} catch (e) { scrap(); throw e; }`;
    const frames = await run(script, { SCREENS, SCREEN_SCRIPT }, ['screens.js']);
    console.log(`${SCREEN_SCRIPT}: ${frames.join(', ')}; ${((Date.now() - started) / 1000).toFixed(1)} s`);
    built.push(...frames);
  }
}
const audit = await run(read('audit.js'), { AUDIT_SECTION: 'Screens', AUDIT_CARDS: names.length ? built : null });
console.log(`audit of ${names.length ? built.join(', ') : 'every screen'}: ${audit.nodes} layers, ${audit.issues.length} issues`);
for (const issue of audit.issues) console.log('  ' + issue);
process.exitCode = audit.issues.length ? 1 : 0;
