// Plugin-side helpers for the card scripts in cards/. build.mjs prepends this
// file to each of them and sets CARD_ORDER, the card's place in the section.
// Every colour, radius, gap, padding, stroke weight, opacity and text style a
// helper sets is bound to a Foundations token, so audit.js can check the result.
await figma.loadAllPagesAsync();
const fail = (what) => { throw new Error('missing in the Figma file: ' + what); };
const PAGE = figma.root.children.find((p) => p.name === 'Redesign') ?? fail('page Redesign');
if (figma.currentPage !== PAGE) await figma.setCurrentPageAsync(PAGE);
const COLLECTIONS = await figma.variables.getLocalVariableCollectionsAsync();
const collection = (name) => COLLECTIONS.find((c) => c.name === name) ?? fail('variable collection ' + name);
const COLOR = {}, DIM = {}, BY_ID = {};
for (const v of await figma.variables.getLocalVariablesAsync()) {
  BY_ID[v.id] = v;
  // Colours are named by their role alone (primary/onPrimary is onPrimary), as in MoshColors.
  if (v.variableCollectionId === collection('Mosh').id) {
    const role = v.name.split('/')[1];
    if (COLOR[role]) fail(`one colour per role: ${COLOR[role].name} and ${v.name}`);
    COLOR[role] = v;
  }
  if (v.variableCollectionId === collection('Mosh Dimensions').id) DIM[v.name] = v;
}
const DIM_MODE = collection('Mosh Dimensions').modes[0].modeId;
const px = (name) => (DIM[name] ?? fail(name)).valuesByMode[DIM_MODE];
const TS = {};
for (const s of await figma.getLocalTextStylesAsync()) TS[s.name.replace('Mosh/', '')] = s;
// Each font once: asking the bridge plugin for a font again and again can leave a load that never resolves.
for (const font of new Set(Object.values(TS).map((s) => JSON.stringify(s.fontName)))) await figma.loadFontAsync(JSON.parse(font));
const ES = {};
for (const s of await figma.getLocalEffectStylesAsync()) ES[s.name.replace('Mosh/', '')] = s;

/** A variable's own colour, following aliases. */
function rgb(v) {
  const value = Object.values(v.valuesByMode)[0];
  if (value.type === 'VARIABLE_ALIAS') return rgb(BY_ID[value.id]);
  return { r: value.r, g: value.g, b: value.b };
}
// The paint starts from the variable's colour: an instance override that binds the
// variable its main component already uses keeps whatever raw colour it was given.
const paint = (c) => [figma.variables.setBoundVariableForPaint({ type: 'SOLID', color: rgb(COLOR[c] ?? fail(c)) }, 'color', COLOR[c])];
const bind = (node, field, name) => node.setBoundVariable(field, DIM[name] ?? fail(name));
const space = (node, field, key) => { if (key) bind(node, field, 'space/' + key); else node[field] = 0; };
const radius = (node, name) => ['topLeftRadius', 'topRightRadius', 'bottomRightRadius', 'bottomLeftRadius'].forEach((f) => bind(node, f, 'radius/' + name));
function stroke(node, color, weight = 'thin', align = 'INSIDE') {
  node.strokes = paint(color); node.strokeAlign = align; bind(node, 'strokeWeight', 'border/' + weight);
}
/** Binds a node's fixed size to space tokens; a null key leaves that axis alone. */
function size(node, wk, hk) {
  node.resize(wk ? px('space/' + wk) : node.width, hk ? px('space/' + hk) : node.height);
  if (wk) bind(node, 'width', 'space/' + wk);
  if (hk) bind(node, 'height', 'space/' + hk);
}

// Auto-layout frame or component. o: component, dir 'H'|'V', gap and pad as
// space keys (pad: n | [v, h] | [t, r, b, l]), fill and stroke as colour names,
// sw 'thin'|'thick', r radius name, w/h px or wk/hk space keys, minWk/minHk,
// align, justify, clip, effect.
function box(name, o = {}) {
  const f = o.component ? figma.createComponent() : figma.createFrame();
  f.name = name;
  f.fills = o.fill ? paint(o.fill) : [];
  f.clipsContent = !!o.clip;
  f.layoutMode = o.dir === 'H' ? 'HORIZONTAL' : 'VERTICAL';
  const p = o.pad == null ? [0, 0, 0, 0] : !Array.isArray(o.pad) ? [o.pad, o.pad, o.pad, o.pad] : o.pad.length === 2 ? [o.pad[0], o.pad[1], o.pad[0], o.pad[1]] : o.pad;
  ['paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft'].forEach((k, i) => space(f, k, p[i]));
  space(f, 'itemSpacing', o.gap);
  if (o.stroke) stroke(f, o.stroke, o.sw, o.strokeAlign);
  if (o.r) radius(f, o.r);
  const w = o.w ?? (o.wk && px('space/' + o.wk)), h = o.h ?? (o.hk && px('space/' + o.hk));
  if (w || h) f.resize(w ?? 10, h ?? 10);
  const horizontal = f.layoutMode === 'HORIZONTAL';
  f.primaryAxisSizingMode = (horizontal ? w : h) ? 'FIXED' : 'AUTO';
  f.counterAxisSizingMode = (horizontal ? h : w) ? 'FIXED' : 'AUTO';
  if (o.wk) bind(f, 'width', 'space/' + o.wk);
  if (o.hk) bind(f, 'height', 'space/' + o.hk);
  if (o.minWk) bind(f, 'minWidth', 'space/' + o.minWk);
  if (o.minHk) bind(f, 'minHeight', 'space/' + o.minHk);
  f.counterAxisAlignItems = o.align ?? 'CENTER';
  f.primaryAxisAlignItems = o.justify ?? 'MIN';
  if (o.effect) pendingEffects.push([f, ES[o.effect] ?? fail(o.effect)]);
  return f;
}
function add(parent, child, o = {}) {
  parent.appendChild(child);
  if (o.fillW) child.layoutSizingHorizontal = 'FILL';
  if (o.fillH) child.layoutSizingVertical = 'FILL';
  if (o.abs) { child.layoutPositioning = 'ABSOLUTE'; child.x = o.abs[0]; child.y = o.abs[1]; }
  // A hugging text or frame wraps its content at max px.
  if (o.max) child.maxWidth = o.max;
  return child;
}
// Style ids are set asynchronously, so nodes queue here until flush().
const pendingText = [], pendingEffects = [];
async function flush() {
  for (const [t, s] of pendingText.splice(0)) await t.setTextStyleIdAsync(s.id);
  for (const [n, s] of pendingEffects.splice(0)) await n.setEffectStyleIdAsync(s.id);
}
// Text in a Mosh/* style. o: w (fixed width, wraps), truncate (one line of the width it is given), cut (one line that hugs, cut at add()'s max), name.
function text(chars, slot, color, o = {}) {
  const s = TS[slot] ?? fail(slot), t = figma.createText();
  t.fontName = s.fontName; t.fontSize = s.fontSize; t.lineHeight = s.lineHeight; t.letterSpacing = s.letterSpacing;
  t.characters = chars;
  t.name = o.name ?? chars;
  t.fills = paint(color);
  if (o.w) { t.textAutoResize = 'HEIGHT'; t.resize(o.w, t.height); }
  if (o.truncate) { t.textAutoResize = 'HEIGHT'; t.textTruncation = 'ENDING'; t.maxLines = 1; }
  // One line that hugs its text and is cut where add() caps it with max.
  if (o.cut) { t.textTruncation = 'ENDING'; t.maxLines = 1; }
  pendingText.push([t, s]);
  return t;
}
function rect(name, o = {}) {
  const r = figma.createRectangle();
  r.name = name; r.fills = o.fill ? paint(o.fill) : [];
  r.resize(o.w ?? 10, o.h ?? 10);
  size(r, o.wk, o.hk);
  if (o.r) radius(r, o.r);
  if (o.stroke) stroke(r, o.stroke, o.sw, o.strokeAlign);
  return r;
}
function dot(name, color, key) {
  const e = figma.createEllipse();
  e.name = name; e.fills = paint(color); size(e, key, key);
  return e;
}
const ICONS = {};
for (const c of PAGE.findAllWithCriteria({ types: ['COMPONENT'] })) if (c.name.startsWith('Icon/')) ICONS[c.name.slice(5)] = c;
/** The Icon/<name> component. */
const glyphOf = (name) => ICONS[name] ?? fail('Icon/' + name);
/** An instance of Icon/<name>, recoloured, at a space-token size (5 is 20 px). */
function icon(name, color, key = 5) {
  const i = glyphOf(name).createInstance();
  i.name = 'icon';
  size(i, key, key);
  // The glyph is onSurfaceVariant in its component; only another colour is an override.
  if (color !== 'onSurfaceVariant') i.children[0].fills = paint(color);
  return i;
}
/** A three-quarter ring that stands for a spinning indicator. thick: ring width over the radius. */
function spinner(color, key = 4, thick = 0.25) {
  const e = figma.createEllipse();
  e.name = 'spinner'; size(e, key, key);
  e.arcData = { startingAngle: -Math.PI / 2, endingAngle: Math.PI, innerRadius: 1 - thick };
  e.fills = paint(color);
  return e;
}
/** A state layer or disabled container: a tint over the whole control at a state/* opacity. Call once the control has its size. */
function tint(parent, color, state) {
  const r = figma.createRectangle();
  r.name = 'state layer'; r.fills = paint(color);
  parent.insertChild(0, r);
  r.layoutPositioning = 'ABSOLUTE'; r.x = 0; r.y = 0; r.resize(parent.width, parent.height);
  r.constraints = { horizontal: 'STRETCH', vertical: 'STRETCH' };
  bind(r, 'opacity', 'state/' + state);
  return r;
}
/** Draws a control as disabled: its [content] fades, and with [plate] a faint plate stands in for its fill. */
function disable(control, content, plate = false) {
  for (const node of content) bind(node, 'opacity', 'state/disabledContent');
  if (plate) tint(control, 'onSurface', 'disabledContainer');
}
/** Height of a control as a space key: 40 px on the desktop, 48 px on the phone. */
const controlHeight = (device) => (device === 'Phone' ? 12 : 10);
/** The well of a text field or select: a recessed box whose [edge] colour carries its state. */
function well(parent, { device, edge, thick = false, off = false, pad }) {
  return add(parent, box('well', { dir: 'H', gap: 2, pad, hk: controlHeight(device), r: 'medium', clip: true, fill: off ? null : 'surfaceContainerLowest', stroke: edge, sw: thick ? 'thick' : 'thin' }), { fillW: true });
}
const focusRing = (node) => stroke(node, 'focusRing', 'thick', 'OUTSIDE');
/** Applies hover, pressed and focus to a finished control: a state layer in [color] and, for focus, the ring. */
function interact(node, state, color) {
  const layer = { Hover: 'hover', Pressed: 'pressed', Focus: 'focus' }[state];
  if (layer) tint(node, color, layer);
  if (state === 'Focus') focusRing(node);
}

// --- Section, cards and component sets ---
function host() {
  let s = PAGE.children.find((n) => n.type === 'SECTION' && n.name === 'Components');
  if (!s) { s = figma.createSection(); s.name = 'Components'; s.fills = paint('surfaceDim'); PAGE.appendChild(s); }
  return s;
}
const PAD = 48, ROW_LABEL = 150;
// The components variant() can ask for, by name. Walking the section for each one took most of a build.
const SETS = new Map();
// Last to first, so of two components with one name the first in the section is the one found.
for (const n of host().findAllWithCriteria({ types: ['COMPONENT_SET', 'COMPONENT'] }).reverse()) if (n.parent.type !== 'COMPONENT_SET') SETS.set(n.name, n);
// The card being built, the cards it replaces (null for a card updated in place) and the y where its next block goes.
let CARD, OLD = null, cursor;
/** A fresh card for one component family. The card of the same name stays beside it until finish() has moved its instances over. */
function card(name, note) {
  const s = host();
  OLD = s.children.filter((n) => n.name === name);
  for (const [key, n] of SETS) if (OLD.includes(n.parent)) SETS.delete(key);
  const c = CARD = figma.createFrame();
  c.name = name; c.setPluginData('order', String(CARD_ORDER)); c.fills = paint('surfaceContainerLow'); radius(c, 'extraLarge'); c.clipsContent = false;
  s.appendChild(c);
  add(c, text(name, 'headlineSmall', 'onSurface')).y = PAD;
  const n = add(c, text(note, 'bodyMedium', 'onSurfaceVariant', { w: 860 })); n.y = PAD + 40;
  c.children.forEach((k) => { k.x = PAD; });
  cursor = n.y + n.height + 32;
  c.resize(960, 200);
  return c;
}
/**
 * Adds a component set to the card as a labelled grid. rows and cols are
 * [label, {Property: value}] pairs; make(props) returns the variant.
 * A grid of one cell stays a plain component. minCol keeps the column labels of narrow variants apart.
 */
async function grid(name, rows, cols, make, minCol = 0) {
  const c = CARD;
  const cells = [];
  for (const [, rp] of rows) for (const [, cp] of cols) {
    const props = { ...rp, ...cp }, v = await make(props);
    v.name = Object.entries(props).map(([k, x]) => `${k}=${x}`).join(', ') || name;
    cells.push(v);
  }
  await flush();
  const colW = cols.map((_, j) => Math.max(minCol, ...rows.map((_, i) => cells[i * cols.length + j].width)));
  const rowH = rows.map((_, i) => Math.max(...cols.map((_, j) => cells[i * cols.length + j].height)));
  const GAP = 32, IN = 24;
  let y = cursor;
  add(c, text(name, 'titleMedium', 'onSurface')).y = y; c.children.at(-1).x = PAD;
  y += 40;
  const labelled = rows.some(([l]) => l), left = PAD + (labelled ? ROW_LABEL : 0);
  let x = left + IN;
  cols.forEach(([label], j) => { if (label) { const t = add(c, text(label, 'labelMedium', 'onSurfaceMuted')); t.x = x; t.y = y; } x += colW[j] + GAP; });
  if (cols.some(([l]) => l)) y += 28;
  const single = cells.length === 1;
  const set = single ? cells[0] : figma.combineAsVariants(cells, c);
  if (single) c.appendChild(set); else { set.name = name; set.fills = []; set.cornerRadius = 0; }
  const W = colW.reduce((a, b) => a + b, 0) + GAP * (cols.length - 1) + IN * 2, H = rowH.reduce((a, b) => a + b, 0) + GAP * (rows.length - 1) + IN * 2;
  let cy = IN;
  rows.forEach(([label], i) => {
    let cx = IN;
    cols.forEach((_, j) => { const v = cells[i * cols.length + j]; if (!single) { v.x = cx; v.y = cy; } cx += colW[j] + GAP; });
    if (label) { const t = add(c, text(label, 'labelMedium', 'onSurfaceMuted')); t.x = PAD; t.y = y + cy + rowH[i] / 2 - 8; }
    cy += rowH[i] + GAP;
  });
  if (single) { set.name = name; set.x = left + IN; set.y = y + IN; } else { set.resizeWithoutConstraints(W, H); set.x = left; set.y = y; }
  await flush();
  y += H + 40;
  cursor = y;
  c.resize(Math.max(c.width, left + W + PAD), y + PAD - 40);
  SETS.set(name, set);
  return set;
}
/** Adds a row of usage examples (instances) under the sets of the card; align 'MIN' levels their tops. */
async function examples(label, nodes, align = 'CENTER') {
  const c = CARD;
  let y = cursor;
  const t = add(c, text(label, 'titleMedium', 'onSurface')); t.x = PAD; t.y = y;
  const row = box('Examples · ' + label, { dir: 'H', gap: 2, align });
  c.appendChild(row); row.x = PAD; row.y = y + 40;
  nodes.forEach((n) => row.appendChild(n));
  await flush();
  y = row.y + row.height + 40;
  cursor = y;
  c.resize(Math.max(c.width, row.width + PAD * 2), y + PAD - 40);
  return row;
}
const variants = (set) => (set.type === 'COMPONENT_SET' ? set.children : [set]);
/** Exposes the layers called [layer] in every variant as one component property. */
function prop(set, name, type, value, layer) {
  const key = set.addComponentProperty(name, type, type === 'INSTANCE_SWAP' ? value.id : value);
  const field = { TEXT: 'characters', BOOLEAN: 'visible', INSTANCE_SWAP: 'mainComponent' }[type];
  const nested = (n, top) => { for (let p = n.parent; p !== top; p = p.parent) if (p.type === 'INSTANCE') return true; return false; };
  for (const v of variants(set)) for (const n of v.findAll((x) => x.name === layer && !nested(x, v))) {
    n.componentPropertyReferences = { ...(n.componentPropertyReferences ?? {}), [field]: key };
  }
}
/** Stacks the cards in build order into columns no taller than the Foundations section beside them. */
function layoutCards() {
  const s = host(), GAP = 64, MAX = 6600;
  let x = GAP, y = GAP, colW = 0, bottom = 0;
  for (const c of [...s.children].sort((a, b) => a.getPluginData('order') - b.getPluginData('order'))) {
    if (y > GAP && y + c.height > MAX) { x += colW + GAP; y = GAP; colW = 0; }
    c.x = x; c.y = y; y += c.height + GAP; colW = Math.max(colW, c.width); bottom = Math.max(bottom, y);
  }
  s.resizeWithoutConstraints(x + colW + GAP, bottom);
  // Beside Foundations, top edges level.
  const f = PAGE.children.find((n) => n.name === 'Foundations');
  s.x = f.x + f.width + 200; s.y = f.y;
}
/** Ends a card script: moves the instances of the replaced card onto this one (relink.js), places the card and reports what it holds. */
async function finish() {
  const moved = OLD?.length ? await relink(OLD, CARD) : {};
  OLD?.forEach((o) => o.remove());
  layoutCards();
  return { card: CARD.name, sets: CARD.findAllWithCriteria({ types: ['COMPONENT_SET'] }).map((x) => `${x.name} ${x.children.length}`), ...moved };
}
/** Wraps a control's [visual] as a variant; on the phone it sits in a transparent tap target of at least 48 by 48 px. */
function shell(name, visual, device) {
  const phone = device === 'Phone';
  const c = box(name, { component: true, dir: 'H', minHk: phone ? 12 : null, minWk: phone ? 12 : null, justify: 'CENTER' });
  add(c, visual);
  return c;
}
/** A component built earlier: the variant of [setName] matching [props]. */
function variant(setName, props = {}) {
  const set = SETS.get(setName) ?? fail(setName);
  const v = set.type === 'COMPONENT' ? set : set.children.find((c) => Object.entries(props).every(([k, x]) => c.name.split(', ').includes(`${k}=${x}`)));
  return v ?? fail(setName + ' ' + JSON.stringify(props));
}
const inst = (setName, props) => variant(setName, props).createInstance();
/** Sets component properties of an instance by their display names. */
function setProps(i, values) {
  for (const [name, value] of Object.entries(values)) {
    const key = Object.keys(i.componentProperties).find((k) => k.split('#')[0] === name) ?? fail('property ' + name);
    // Setting a swap to the component it already shows resets the nested instance, size and name included.
    if (i.componentProperties[key].value !== (value?.id ?? value)) i.setProperties({ [key]: value?.id ?? value });
  }
  return i;
}
/** An Icon button showing [glyph]; ink recolours the glyph where its own colour would not read. */
function action(glyph, Device, { Kind = 'Standard', State = 'Default', ink } = {}) {
  const b = setProps(inst('Icon button', { Kind, State, Device }), { 'Icon glyph': glyphOf(glyph) });
  if (ink) b.findOne((n) => n.name === 'glyph').fills = paint(ink);
  return b;
}
// What sits in a bubble is drawn for both of its colours: the inks of each.
const TONES = {
  Surface: { ink: 'onSurface', quiet: 'onSurfaceMuted', plate: 'surfaceContainerHighest', glyph: 'onSurfaceVariant', error: 'error', failPlate: 'errorContainer', accent: 'primary', onAccent: 'onPrimary', rest: 'outline' },
  Outgoing: { ink: 'onOutgoing', quiet: 'onOutgoingVariant', plate: 'onOutgoingVariant', glyph: 'outgoing', error: 'outgoingError', failPlate: 'outgoingError', accent: 'onOutgoing', onAccent: 'outgoing', rest: 'onOutgoingVariant' },
};
const toneRows = (rows) => Object.keys(TONES).flatMap((t) => rows.map(([label, props]) => [[label, t.toLowerCase()].filter(Boolean).join(', '), { ...props, Tone: t }]));
/** Lays the outgoing bubble under the variants of [set] drawn for it, which the card's own colour would hide: its colour, its 20 px corners and its 8 px padding, so a 12 px corner inside reads concentric as it will in a message. */
function backdrop(set) {
  const at = CARD.children.indexOf(set), M = 8;
  for (const v of variants(set).filter((x) => x.name.includes('Tone=Outgoing'))) {
    const r = rect('outgoing bubble', { fill: 'outgoing', w: v.width + M * 2, h: v.height + M * 2, r: 'largeIncreased' });
    CARD.insertChild(at, r);
    r.x = set.x + v.x - M; r.y = set.y + v.y - M;
  }
  return set;
}
// Widths a component is drawn at: a row of the chat list, the feed of a conversation, and the text of a bubble.
const ROW = { Desktop: 324, Phone: 358 }, FEED = { Desktop: 640, Phone: 390 }, MEASURE = { Desktop: 480, Phone: 232 };
// Text in a bubble, and the caption of a picture, is set in a little further than the bubble's 8 px padding.
const INSET = [0, 1, 0, 2];
/** Width of the text line of a bubble: the measure and the inset of the text on both sides. An attachment on the phone is this wide, so a caption never outgrows it. */
const lineWidth = (Device) => MEASURE[Device] + px('space/' + INSET[1]) + px('space/' + INSET[3]);
/** Width of a file or media card. A caption under it wraps at this width, as the bubble is no wider than the card. */
const attachmentWidth = (Device) => (Device === 'Desktop' ? 320 : lineWidth(Device));
/** Side padding of the feed, as a space key. */
const feedPad = (Device) => (Device === 'Phone' ? 3 : 5);
/** Adds an Avatar that the instances of the component can swap and set: its layer is exposed. */
function avatarSlot(parent, props) {
  const a = add(parent, inst('Avatar', { Kind: 'Person', Plate: '2', ...props }));
  a.name = 'avatar'; a.isExposedInstance = true;
  return a;
}
/** Turns the avatar inside [node] into another variant and sets its properties. */
function dressAvatar(node, props, values = {}) {
  const a = node.findOne((n) => n.name === 'avatar');
  a.swapComponent(variant('Avatar', { Kind: 'Person', ...props }));
  return setProps(a, values);
}
/** The chat list's filters, the first one lit. */
function filterChips(Device) {
  const row = box('filters', { dir: 'H', gap: 1 });
  ['All', 'Personal', 'Groups', 'Channels'].forEach((l, i) => add(row, setProps(inst('Filter chip', { Selected: i ? 'No' : 'Yes', State: 'Default', Device }), { Label: l })));
  return row;
}
/** The All / Files switch of a search; files: Files is the lit one. */
function segmented(Device, files = false) {
  const control = box('Segmented control', { dir: 'H', pad: 1, gap: 1, r: 'full', fill: 'surfaceContainerLowest' });
  add(control, setProps(inst('Segment', { Selected: files ? 'No' : 'Yes', State: 'Default', Device }), { Label: 'All' }));
  add(control, setProps(inst('Segment', { Selected: files ? 'Yes' : 'No', State: 'Default', Device }), { Label: 'Files', Icon: true }));
  return control;
}
/** Names the file or media card [card]. A name too long for it is cut in the middle: its start, an ellipsis and its last characters, extension included. */
function nameFile(card, name) {
  const label = card.findOne((n) => n.type === 'TEXT' && n.visible && n.name.startsWith('name') && n.name !== 'name end');
  const end = card.findOne((n) => n.name === 'name end'), KEPT = 9;
  // A media card has a name property per kind; the label knows which one is its own.
  const key = label.componentPropertyReferences.characters;
  setProps(card, { 'Name end': '' }).setProperties({ [key]: name });
  // Figma cuts a text only at its end, so the start is shortened here until it fits beside the end.
  if (label.width < label.maxWidth) return card;
  setProps(card, { 'Name end': name.slice(-KEPT) });
  for (let start = name.slice(0, -KEPT); label.width + end.width > label.maxWidth && start.length > 1;) {
    start = start.slice(0, -1);
    card.setProperties({ [key]: start + '…' });
  }
  return card;
}
/** Marks a set that is not one target itself: it is read, holds targets of its own, or is pressed together with the padding of what holds it. audit.js asks no phone tap target of the set as a whole. */
function display(set) { set.setPluginData('target', 'none'); return set; }
// Grid axes are [label, {Property: value}] pairs; ONE is the axis of a property-less component.
const ONE = [['', {}]];
const axis = (property, values) => values.map((v) => [v, { [property]: v }]);
const STATES5 = axis('State', ['Default', 'Hover', 'Pressed', 'Focus', 'Disabled']);
/** Every control is drawn for the desktop and the phone: [rows] once per device, or a row per device. */
function perDevice(rows = ONE) {
  return ['Desktop', 'Phone'].flatMap((d) => rows.map(([label, props]) => [[label, d].filter(Boolean).join(', '), { ...props, Device: d }]));
}
const DEVICES = axis('Device', ['Desktop', 'Phone']);
