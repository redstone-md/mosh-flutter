// Creates the Mosh colour variables and text styles in the Figma file. Idempotent:
// existing variables and styles are updated in place.
import fs from 'node:fs';
import { REPO } from './areas.mjs';
import { execute } from './mcp.mjs';

const src = fs.readFileSync(`${REPO}lib/src/app/mosh_colors.dart`, 'utf8');
const colors = {};
for (const m of src.matchAll(/static const Color (\w+) =\s*Color\(0x([0-9A-Fa-f]{8})\)/g)) {
  const h = m[2];
  const a = parseInt(h.slice(0, 2), 16) / 255;
  colors[m[1]] = { r: parseInt(h.slice(2, 4), 16) / 255, g: parseInt(h.slice(4, 6), 16) / 255, b: parseInt(h.slice(6, 8), 16) / 255, a };
}

const group = (n) =>
  /^bg\d/.test(n) ? 'surface' : /^fg\d/.test(n) ? 'text' : /^line|Border$|focusRing/.test(n) ? 'line'
  : /^moss/.test(n) ? 'brand' : /^(warn|danger|info)/.test(n) ? 'status' : 'accent';

// [name, size, weight, height, letterSpacing px] from mosh_typography.dart
const textStyles = [
  ['headlineMedium', 23, 600, 1.15, -0.23], ['headlineSmall', 19, 600, 1.2, -0.19],
  ['titleLarge', 15, 700, 1.25, 0.3], ['titleMedium', 14, 600, 1.3, 0], ['titleSmall', 12.5, 700, 1.3, 0],
  ['bodyLarge', 14, 400, 1.4, 0], ['bodyMedium', 13.5, 400, 1.5, 0], ['bodySmall', 12.5, 400, 1.55, 0],
  ['labelLarge', 12, 600, 1.3, 0], ['labelMedium', 11.5, 600, 1.3, 0], ['labelSmall', 10.5, 400, 1.3, 0],
];

const code = `
const COLORS = ${JSON.stringify(colors)};
const GROUP = ${JSON.stringify(Object.fromEntries(Object.keys(colors).map((n) => [n, group(n)])))};
const STYLES = ${JSON.stringify(textStyles)};
const W = {400:'Regular',500:'Medium',600:'Semi Bold',700:'Bold'};
let col = (await figma.variables.getLocalVariableCollectionsAsync()).find(c => c.name === 'Mosh');
if (!col) col = figma.variables.createVariableCollection('Mosh');
const existing = await figma.variables.getLocalVariablesAsync('COLOR');
let made = 0;
for (const [name, rgba] of Object.entries(COLORS)) {
  const full = GROUP[name] + '/' + name;
  let v = existing.find(x => x.name === full && x.variableCollectionId === col.id);
  if (!v) { v = figma.variables.createVariable(full, col, 'COLOR'); made++; }
  v.setValueForMode(col.modes[0].modeId, rgba);
  v.description = 'MoshColors.' + name;
}
const styles = await figma.getLocalTextStylesAsync();
for (const w of Object.values(W)) await figma.loadFontAsync({family:'Inter', style:w});
for (const [name, size, weight, height, ls] of STYLES) {
  let s = styles.find(x => x.name === 'Mosh/' + name);
  if (!s) s = figma.createTextStyle();
  s.name = 'Mosh/' + name;
  s.fontName = {family:'Inter', style: W[weight]};
  s.fontSize = size;
  s.lineHeight = {unit:'PERCENT', value: height*100};
  s.letterSpacing = {unit:'PIXELS', value: ls};
  s.description = 'Theme.of(context).textTheme.' + name;
}
return {made, colors: Object.keys(COLORS).length};
`;
export const ensureTokens = () => execute(code, 60000);
