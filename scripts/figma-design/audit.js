// Checks the Components section: no value outside the Foundations tokens, and a
// tap target of at least 48 px on every phone variant.
// Not checked, because Foundations has no token for them: widths and heights
// (they are layout, bound to space/* where they sit on the scale), positions,
// the ring geometry of spinners and the caret's rotation.
const issues = [], where = (n) => { const p = []; for (let x = n; x && x.type !== 'SECTION'; x = x.parent) p.unshift(x.name); return p.join(' / '); };
const bad = (n, what) => issues.push(what + ' — ' + where(n));
// A token is a variable of the dark "Mosh" colours or of "Mosh Dimensions"; a binding to anything else does not count.
const TOKENS = new Set([...Object.values(COLOR), ...Object.values(DIM)].map((v) => v.id));
const token = (binding) => TOKENS.has(binding?.id);
const bound = (n, field) => token(n.boundVariables?.[field]);
const styles = Object.fromEntries((await figma.getLocalTextStylesAsync()).map((s) => [s.id, s.name]));
let nodes = 0;
for (const n of host().findAll(() => true)) {
  nodes++;
  for (const key of ['fills', 'strokes']) {
    const paints = n[key];
    if (!Array.isArray(paints)) continue;
    paints.forEach((p) => { if (p.visible !== false && !(p.type === 'SOLID' && token(p.boundVariables?.color))) bad(n, key + ' not a token'); if (p.opacity !== undefined && p.opacity !== 1) bad(n, key + ' paint opacity ' + p.opacity); });
    if (key === 'strokes' && paints.length && !['strokeWeight', 'strokeTopWeight'].some((f) => bound(n, f))) bad(n, 'stroke weight ' + String(n.strokeWeight));
  }
  if (n.type === 'TEXT' && !(styles[n.textStyleId] || '').startsWith('Mosh/')) bad(n, 'text without a Mosh/ style');
  if ('effects' in n && n.effects.length && !n.effectStyleId) bad(n, 'effect without a style');
  if ('opacity' in n && n.opacity !== 1 && !bound(n, 'opacity')) bad(n, 'opacity ' + n.opacity);
  for (const f of ['topLeftRadius', 'topRightRadius', 'bottomRightRadius', 'bottomLeftRadius']) if (f in n && n[f] && !bound(n, f)) bad(n, f + ' ' + n[f]);
  if (n.layoutMode && n.layoutMode !== 'NONE') for (const f of ['paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft', 'itemSpacing']) if (n[f] && !bound(n, f)) bad(n, f + ' ' + n[f]);
}
// A set with a Device property is pressed as a whole and its phone variants need the target,
// unless a card marked it with display(): a message is read, not pressed.
const TARGET = 48;
const sets = Object.fromEntries(host().findAllWithCriteria({ types: ['COMPONENT_SET'] }).map((s) => [s.name, s]));
for (const [name, set] of Object.entries(sets)) {
  if (set.getPluginData('target') === 'none') continue;
  const phone = set.children.filter((v) => v.name.includes('Device=Phone'));
  // A field's target is its well; everything else is pressed as a whole.
  const press = (v) => v.findOne((x) => x.name === 'well') ?? v;
  // Held by a minimum or a fixed size, so a shorter label cannot shrink the target.
  const holds = (n, min, sizing, length) => (n[min] ?? 0) >= TARGET || (n[sizing] !== 'HUG' && n[length] >= TARGET);
  const small = phone.filter((v) => !holds(v, 'minWidth', 'layoutSizingHorizontal', 'width') || !holds(press(v), 'minHeight', 'layoutSizingVertical', 'height'));
  small.forEach((v) => issues.push(`tap target can shrink below ${TARGET} px (${press(v).width}x${press(v).height} now) — ${name} / ${v.name}`));
}
return { nodes, issues, sets: Object.keys(sets).length, variants: Object.values(sets).reduce((n, s) => n + s.children.length, 0) };
