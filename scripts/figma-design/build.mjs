// Builds the redesign's components in the Figma file "Mosh": the "Components"
// section on the Redesign page, one card per family of controls, then checks
// what it built (audit.js). Needs the Desktop Bridge plugin open in the file.
//
//   node build.mjs                every card
//   node build.mjs banner toast   these cards alone
//   node build.mjs banner --on    the banner card and every card after it
//   node build.mjs --audit        only the check, of the whole section
//
// A card is rebuilt from scratch, so its components get new node ids. The
// instances that other cards, and screens outside the section, hold of them
// are then moved onto the new components of the same name (relink.js); the
// other cards keep their components and node ids, and a link to a node in them
// stays good. The check covers the rebuilt cards and the cards whose instances
// moved. What a build of one card cannot do, it says:
//   - a component that is still in use and has no namesake in the new card
//     stops the build, and the old card stays;
//   - Figma keeps the overrides of an instance that is moved: texts, glyph
//     colours, swapped glyphs and avatars. It drops the properties set on an
//     instance nested in another (an avatar's initials in a chat row) when
//     that one only follows its component onto the new card; relink.js sets
//     those again. An override that is gone after the move is listed and
//     fails the build, as Figma may change its rule;
//   - a component of another card that changed size with what it holds is
//     listed: its card laid it out at the old size, so rebuild that card too,
//     or the whole chain with --on.
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { execute } from '../figma-capture/mcp.mjs';

// In build order: a card may use the components of the cards before it.
const CARDS = ['icons', 'button', 'icon-button', 'text-field', 'select', 'switch', 'chips', 'avatar', 'badges', 'progress', 'slider-divider', 'attachment', 'voice', 'message', 'feed', 'thread', 'composer', 'chat-row', 'chat-list', 'org', 'search', 'dialog', 'menu', 'banner', 'toast', 'title-bar', 'settings', 'details', 'wizard', 'empty', 'media-viewer', 'levels'];
const read = (file) => fs.readFileSync(new URL(file, import.meta.url), 'utf8');
/** Runs a plugin script with the helpers of lib.js, surfaces.js and relink.js before it; consts are the values it is given. */
function run(script, consts = {}) {
  const given = Object.entries(consts).map(([name, value]) => `const ${name} = ${JSON.stringify(value)};\n`).join('');
  return execute(`${given}${['lib.js', 'surfaces.js', 'relink.js'].map(read).join('\n')}\n${script}`, 280000);
}

/** icons.json maps an icon's role in the controls to its Phosphor name; returns the role's 24 px SVG. */
function iconSvg() {
  const phosphor = createRequire(import.meta.url)('@iconify-json/ph/icons.json');
  return Object.fromEntries(Object.entries(JSON.parse(read('icons.json'))).map(([role, name]) => {
    const icon = phosphor.icons[name];
    if (!icon) throw new Error(`icons.json: Phosphor has no "${name}" (${role})`);
    return [role, `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 ${phosphor.width} ${phosphor.height}">${icon.body}</svg>`];
  }));
}

/** The places in CARDS of the cards the arguments ask for, in build order. */
function chosen(args) {
  const names = args.filter((a) => !a.startsWith('--'));
  const unknown = names.filter((n) => !CARDS.includes(n));
  if (unknown.length) throw new Error(`no card "${unknown.join('", "')}"; cards: ${CARDS.join(', ')}`);
  if (!names.length) return [...CARDS.keys()];
  if (!args.includes('--on')) return [...CARDS.keys()].filter((order) => names.includes(CARDS[order]));
  if (names.length > 1) throw new Error('--on takes one card: the build runs from it to the last');
  return [...CARDS.keys()].slice(CARDS.indexOf(names[0]));
}

/** Rebuilds the cards at [orders]; returns the names of the cards to check and the overrides lost on the way. */
async function build(orders) {
  const touched = new Set(), lost = [];
  console.log('tokens', JSON.stringify(await run(read('tokens.js'))));
  for (const [at, order] of orders.entries()) {
    const started = Date.now();
    // Read when its turn comes, so a card edited during a long run is built as edited.
    const script = `try {\n${read(`cards/${CARDS[order]}.js`)}\nreturn await finish();\n} catch (e) { discard(); throw e; }`;
    const consts = { CARD_ORDER: order, REBUILT_LATER: orders.slice(at + 1), ...(CARDS[order] === 'icons' ? { ICON_SVG: iconSvg() } : {}) };
    const { card, sets, moved = 0, touched: users = [], lost: dropped = [], resized = [] } = await run(script, consts);
    console.log(`${card}: ${sets.join(', ') || 'no sets'}; ${moved} instances moved; ${((Date.now() - started) / 1000).toFixed(1)} s`);
    for (const line of resized) console.log(`  changed size, rebuild its card: ${line}`);
    [card, ...users].forEach((name) => touched.add(name));
    lost.push(...dropped);
  }
  return { cards: orders.length === CARDS.length ? null : [...touched], lost };
}

const args = process.argv.slice(2);
const { cards, lost } = args.includes('--audit') ? { cards: null, lost: [] } : await build(chosen(args));
const audit = await run(read('audit.js'), { AUDIT_CARDS: cards });
const issues = [...lost.map((line) => `override lost in the move: ${line}`), ...audit.issues];
console.log(`audit of ${cards ? cards.join(', ') : 'every card'}: ${audit.nodes} layers, ${audit.sets} sets with ${audit.variants} variants, ${issues.length} issues`);
for (const issue of issues) console.log('  ' + issue);
process.exitCode = issues.length ? 1 : 0;
