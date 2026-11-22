// Builds the redesign's components in the Figma file "Mosh": the "Components"
// section on the Redesign page, one card per family of controls, then checks
// the section (audit.js). Needs the Desktop Bridge plugin open in the file.
//
//   node build.mjs            every card
//   node build.mjs select     the select card and every card after it
//   node build.mjs --audit    only the check
//
// A card is rebuilt from scratch, which detaches the instances that later
// cards hold of its components; that is why a build runs on to the end.
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { execute } from '../figma-capture/mcp.mjs';

// In build order: a card may use the components of the cards before it.
const CARDS = ['icons', 'button', 'icon-button', 'text-field', 'select', 'switch', 'chips', 'avatar', 'badges', 'progress', 'slider-divider'];
const read = (file) => fs.readFileSync(new URL(file, import.meta.url), 'utf8');
/** Runs a plugin script with the helpers of lib.js before it. */
const run = (script, prelude = '') => execute(`${prelude}${read('lib.js')}\n${script}`, 280000);

/** icons.json maps an icon's role in the controls to its Phosphor name; returns the role's 24 px SVG. */
function iconSvg() {
  const phosphor = createRequire(import.meta.url)('@iconify-json/ph/icons.json');
  return Object.fromEntries(Object.entries(JSON.parse(read('icons.json'))).map(([role, name]) => {
    const icon = phosphor.icons[name];
    if (!icon) throw new Error(`icons.json: Phosphor has no "${name}" (${role})`);
    return [role, `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 ${phosphor.width} ${phosphor.height}">${icon.body}</svg>`];
  }));
}

const [arg] = process.argv.slice(2);
if (arg !== '--audit') {
  const from = arg ? CARDS.indexOf(arg) : 0;
  if (from < 0) throw new Error(`no card "${arg}"; cards: ${CARDS.join(', ')}`);
  console.log('tokens', JSON.stringify(await run(read('tokens.js'))));
  for (const [order, name] of CARDS.entries()) {
    if (order < from) continue;
    const icons = name === 'icons' ? `const ICON_SVG = ${JSON.stringify(iconSvg())};\n` : '';
    console.log(JSON.stringify(await run(`${read(`cards/${name}.js`)}\nreturn finish();`, `const CARD_ORDER = ${order};\n${icons}`)));
  }
}
const audit = await run(read('audit.js'));
console.log(`audit: ${audit.nodes} layers, ${audit.sets} sets with ${audit.variants} variants, ${audit.issues.length} issues`);
for (const issue of audit.issues) console.log('  ' + issue);
process.exitCode = audit.issues.length ? 1 : 0;
