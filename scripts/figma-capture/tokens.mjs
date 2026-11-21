// Writes the theme's colours and type scale to the Figma file as the "Mosh"
// variable collection and the Mosh/* text styles. Idempotent: existing
// variables and styles are updated in place, and a file that already holds the
// theme's values does not change.
import fs from 'node:fs';
import path from 'node:path';
import { REPO } from './areas.mjs';
import { execute } from './mcp.mjs';

const read = (file) => fs.readFileSync(path.join(REPO, 'lib', 'src', 'app', file), 'utf8');

/** Figma groups its variables; a token's group follows from its name. */
const GROUPS = [
  // Mosh roles filed outside the group their name suggests.
  [/^outgoingMessage$/, 'accent'], [/^info$/, 'status'], [/^focusRing$/, 'line'],
  // Material 3 roles and the Mosh roles beside them.
  [/^(on)?Primary|^primary|^inversePrimary$/, 'primary'], [/^(on)?[Ss]econdary/, 'secondary'],
  [/^(on)?[Tt]ertiary/, 'tertiary'], [/^(on)?[Ee]rror/, 'error'], [/[Ss]urface/, 'surface'], [/^outline/, 'outline'],
  [/^success$|[Ww]arning/, 'status'], [/[Oo]utgoing|^incoming$/, 'message'], [/[Aa]vatar/, 'avatar'],
];
const group = (name) => {
  const hit = GROUPS.find(([pattern]) => pattern.test(name));
  if (!hit) throw new Error(`mosh_colors.dart: no Figma group for ${name}`);
  return hit[1];
};

let parsed;
/** What the theme defines, read once per run: { colors: {path: rgba}, aliases: {path: path}, family, styles }. */
export function themeTokens() {
  return (parsed ??= parseTheme());
}

function parseTheme() {
  const src = read('mosh_colors.dart');
  const colors = {}, aliases = {};
  const full = (name) => `${group(name)}/${name}`;
  for (const m of src.matchAll(/static const Color (\w+) =\s*Color\(0x([0-9A-Fa-f]{8})\)/g)) {
    const [a, r, g, b] = [0, 2, 4, 6].map((i) => parseInt(m[2].slice(i, i + 2), 16) / 255);
    colors[full(m[1])] = { r, g, b, a };
  }
  // A token defined as another token (info = tertiary) is an alias variable.
  for (const m of src.matchAll(/static const Color (\w+) =\s*(\w+);/g)) {
    if (!colors[full(m[2])]) throw new Error(`mosh_colors.dart: ${m[1]} must name a literal token, not ${m[2]}`);
    aliases[full(m[1])] = full(m[2]);
  }
  const type = read('mosh_typography.dart');
  const family = type.match(/_kSansFamily = '([^']+)'/)[1];
  // [slot, size, line box px, weight, letter-spacing px] from the _slot() calls.
  const styles = [...type.matchAll(/(\w+): _slot\(\s*([\d.]+),\s*([\d.]+)([^)]*)\)/g)].map(([, slot, size, line, rest]) =>
    [slot, +size, +line, +(rest.match(/FontWeight\.w(\d+)/)?.[1] ?? 400), +(rest.match(/spacing: (-?[\d.]+)/)?.[1] ?? 0)]);
  if (!Object.keys(colors).length || !styles.length) throw new Error('no tokens parsed from the theme');
  return { colors, aliases, family, styles };
}

/** Figma's style name of each weight the theme bundles. */
export const WEIGHT_STYLES = { 400: 'Regular', 500: 'Medium', 600: 'SemiBold', 700: 'Bold' };

// Runs in the plugin with T (themeTokens), W (WEIGHT_STYLES) and DRY. Returns the
// changes it made, or with DRY the changes it would make.
const sync = `
const changes = [];
const close = (a, b) => Math.abs(a - b) < 0.5 / 255;
let col = (await figma.variables.getLocalVariableCollectionsAsync()).find((c) => c.name === 'Mosh');
if (!col) { changes.push('collection Mosh'); if (DRY) return changes; col = figma.variables.createVariableCollection('Mosh'); }
const mode = col.modes[0].modeId;
const vars = (await figma.variables.getLocalVariablesAsync('COLOR')).filter((v) => v.variableCollectionId === col.id);
const ensure = (name) => {
  let v = vars.find((x) => x.name === name);
  if (!v) {
    changes.push('new ' + name);
    if (DRY) return null;
    v = figma.variables.createVariable(name, col, 'COLOR');
    v.description = 'MoshColors.' + name.split('/')[1];
    vars.push(v);
  }
  return v;
};
for (const [name, c] of Object.entries(T.colors)) {
  const v = ensure(name), now = v && v.valuesByMode[mode];
  if (now && 'r' in now && ['r', 'g', 'b', 'a'].every((k) => close(now[k], c[k]))) continue;
  if (v) changes.push('value ' + name);
  if (!DRY) v.setValueForMode(mode, c);
}
for (const [name, target] of Object.entries(T.aliases)) {
  const v = ensure(name), base = vars.find((x) => x.name === target), now = v && v.valuesByMode[mode];
  if (now && base && now.type === 'VARIABLE_ALIAS' && now.id === base.id) continue;
  if (v) changes.push('alias ' + name + ' -> ' + target);
  if (!DRY) v.setValueForMode(mode, { type: 'VARIABLE_ALIAS', id: base.id });
}
const known = new Set([...Object.keys(T.colors), ...Object.keys(T.aliases)]);
for (const v of vars) if (!known.has(v.name)) changes.push('not in the theme: ' + v.name);
const styles = await figma.getLocalTextStylesAsync();
for (const [slot, size, line, weight, spacing] of T.styles) {
  const want = { family: T.family, style: W[weight] };
  let s = styles.find((x) => x.name === 'Mosh/' + slot);
  const same = s && s.fontName.family === want.family && s.fontName.style === want.style && s.fontSize === size &&
    s.lineHeight.unit === 'PERCENT' && Math.abs(s.lineHeight.value - (line / size) * 100) < 0.01 &&
    s.letterSpacing.unit === 'PIXELS' && Math.abs(s.letterSpacing.value - spacing) < 0.001;
  if (same) continue;
  changes.push((s ? 'style ' : 'new style ') + slot);
  if (DRY) continue;
  await figma.loadFontAsync(want);
  if (!s) { s = figma.createTextStyle(); s.name = 'Mosh/' + slot; s.description = 'Theme.of(context).textTheme.' + slot; }
  s.fontName = want;
  s.fontSize = size;
  s.lineHeight = { unit: 'PERCENT', value: (line / size) * 100 };
  s.letterSpacing = { unit: 'PIXELS', value: spacing };
}
return changes;
`;

/** Syncs the file to the theme and returns what changed; [dry] only reports. */
export const ensureTokens = (dry = false) => execute(
  `const T = ${JSON.stringify(themeTokens())};\nconst W = ${JSON.stringify(WEIGHT_STYLES)};\nconst DRY = ${dry};\n${sync}`, 60000);

/** The colour the window paints beneath the app (MoshColors.surface), as [r, g, b] in 0–1. */
export function windowColor() {
  const { r, g, b } = themeTokens().colors['surface/surface'];
  return [r, g, b];
}
