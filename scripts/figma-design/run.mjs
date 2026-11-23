// What build.mjs (components) and screens.mjs (screens) share: running a plugin
// script in the Figma file "Mosh" with the helpers every script of this folder
// builds on, reading a command line, and checking a section of the page. A card
// and a screen are assembled, guarded and checked by the same code.
import fs from 'node:fs';
import { execute } from '../figma-capture/mcp.mjs';

export const read = (file) => fs.readFileSync(new URL(file, import.meta.url), 'utf8');
// In this order: each file may use what the ones before it define.
const PRELUDE = ['lib.js', 'surfaces.js', 'calls.js', 'compose.js', 'relink.js'];
/** Runs [script] with the prelude before it; consts are the values it is given, extra the files that follow the prelude. */
export function run(script, consts = {}, extra = []) {
  const given = Object.entries(consts).map(([name, value]) => `const ${name} = ${JSON.stringify(value)};\n`).join('');
  return execute(`${given}${[...PRELUDE, ...extra].map(read).join('\n')}\n${script}`, 280000);
}

/** The script in [file] as it is run: [end] closes it, and one that throws takes back what it had made (discard() of relink.js). Read when called, so a script edited during a long run is built as edited. */
export const guarded = (file, end) => `try {\n${read(file)}\nreturn await ${end}();\n} catch (e) { discard(); throw e; }`;

/**
 * Reads a command line: the names it gives out of [known], and its flags out of --audit and [flags].
 * Anything else throws, so a mistyped name or flag cannot fall through to a build of everything. --audit stands alone.
 */
export function parse(args, known, flags = []) {
  const names = args.filter((a) => !a.startsWith('--')), given = args.filter((a) => a.startsWith('--'));
  const stray = [...given.filter((f) => !['--audit', ...flags].includes(f)), ...names.filter((n) => !known.includes(n))];
  if (stray.length || (given.includes('--audit') && args.length > 1)) throw new Error(`cannot read "${stray.join(' ') || args.join(' ')}"; names: ${known.join(', ')}; flags: ${['--audit', ...flags].join(', ')}`);
  return { names, audit: given.includes('--audit'), has: (flag) => given.includes(flag) };
}

/** Checks [section] with audit.js, or only what [names] names in it, prints the issues with those [found] on the way, and sets the exit code. */
export async function check(section, names, found = []) {
  const audit = await run(read('audit.js'), { AUDIT_SECTION: section, AUDIT_NAMES: names });
  const issues = [...found, ...audit.issues];
  console.log(`audit of ${names ? audit.checked.join(', ') : `all of ${section}`}: ${audit.nodes} layers, ${audit.sets} sets with ${audit.variants} variants, ${issues.length} issues`);
  for (const issue of issues) console.log('  ' + issue);
  process.exitCode = issues.length ? 1 : 0;
}
