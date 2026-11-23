// Runs a plugin script in the Figma file "Mosh" with the helpers every script
// of this folder builds on. build.mjs (components) and screens.mjs (screens)
// both go through here, so a card and a screen are assembled by the same code.
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
