// Plugin-side helpers for surfaces and what stands on them: run.mjs prepends
// this file after lib.js. A surface takes its colour, edge, corners and shadow
// from its level here. The tones under and
// inside the levels (BENEATH, inset, plate) are named here too, so no card
// picks a surface colour of its own. Below them: the toned notice and the
// screens a surface is shown lying over.

// The four levels a surface can sit on, lowest first. The background is the
// screen itself; a panel is a part of the screen (the chat list, the title bar,
// a card of settings); a popup floats over the screen until its choice is made
// (menu, toast); a modal stops the screen and always lies on the scrim.
// Popup and modal share a tone: the edge and the shadow lift both off whatever
// is under them, and the scrim alone says that the screen is stopped.
const LEVEL = {
  background: { fill: 'surface' },
  panel: { fill: 'surfaceContainerLow' },
  popup: { fill: 'surfaceContainerHigh', stroke: 'outlineVariant', effect: 'elevation2', r: 'large' },
  modal: { fill: 'surfaceContainerHigh', stroke: 'outlineVariant', effect: 'elevation3', r: 'extraLarge' },
};
// Under every level: the scrim, and what shows a picture and wants nothing brighter than it: the stage of the media viewer, the open call and the phone's call strip.
const BENEATH = 'surfaceContainerLowest';
/** A box on one of the LEVELs; o as for box(). */
const surface = (name, level, o = {}) => box(name, { ...(LEVEL[level] ?? fail('level ' + level)), ...o });
/** A panel drawn as a card inside the background: the panel's tone with a quiet edge. */
const cardSurface = (name, o = {}) => surface(name, 'panel', { stroke: 'outlineVariant', r: 'extraLarge', ...o });
/** Padding of a card, as a space key. */
const cardPad = (Device) => (Device === 'Phone' ? 4 : 5);
/** A plate set into a card to hold one thing apart (a device, a code): a tone up, with corners concentric to the card's. */
const inset = (name, o = {}) => box(name, { fill: 'surfaceContainer', r: 'small', ...o });

/** The plate with the icon of a card's subject. */
function plate(glyph) {
  const p = box('plate', { dir: 'H', wk: 10, hk: 10, r: 'medium', fill: 'surfaceContainerHighest', justify: 'CENTER' });
  add(p, icon(glyph, 'primary'));
  return p;
}
/**
 * The header of a card: plate, title, a line about it and, at the right, [tail].
 * The plate keeps its place at the top however long the line runs; the title alone, and the tail, sit level with the plate's middle.
 */
function header(parent, glyph, title, line, tail) {
  const h = add(parent, box('header', { dir: 'H', gap: 3, align: 'MIN' }), { fillW: true });
  add(h, plate(glyph));
  const col = add(h, box('text', { dir: 'V', align: 'MIN', justify: 'CENTER', minHk: 10 }), { fillW: true });
  para(col, title, 'titleMedium', 'onSurface', 'title');
  if (line) para(col, line, 'bodySmall', 'onSurfaceVariant', 'line');
  if (tail) add(add(h, box('tail', { dir: 'H', hk: 10 })), tail);
  return h;
}
/** A Button by its label (button() is the Button card's own builder). o: Kind, State, glyph (shows the leading icon). */
function labelButton(Device, Label, { Kind = 'Primary', State = 'Default', glyph } = {}) {
  return setProps(inst('Button', { Kind, Device, State }), glyph ? { Label, Icon: true, 'Icon glyph': glyphOf(glyph) } : { Label });
}
/** A Button turned destructive: the error colour takes the place of the primary one. */
function danger(Device, Label, glyph) {
  const b = labelButton(Device, Label, { glyph });
  b.fills = paint('error');
  b.findOne((n) => n.type === 'TEXT').fills = paint('onError');
  if (glyph) b.findOne((n) => n.name === 'glyph').fills = paint('onError');
  return b;
}
/** Text that wraps at the width of what holds it. */
const para = (parent, chars, slot, color, name) => add(parent, text(chars, slot, color, { name, w: 200 }), { fillW: true });
/** The scrim over [frame]: everything already in it goes dark, what is added after lies above. */
function dim(frame) {
  const s = inst('Scrim');
  frame.appendChild(s);
  s.layoutPositioning = 'ABSOLUTE'; s.x = 0; s.y = 0; s.resize(frame.width, frame.height);
  s.constraints = { horizontal: 'STRETCH', vertical: 'STRETCH' };
  return s;
}
/** A title over a line about it, both wrapping at the width of [parent]. title and line are [chars, text style, colour]. */
function titled(parent, title, line, centred = false) {
  for (const [i, [chars, slot, ink]] of [title, line].entries()) {
    const t = para(parent, chars, slot, ink, i ? 'line' : 'title');
    if (centred) t.textAlignHorizontal = 'CENTER';
  }
}
// Widths of a dialog (and of a note or a notice inside a card), and of the phone's screen, which a sheet spans.
const DIALOG = { Desktop: 400, Phone: 326 }, PHONE_SCREEN = 390;

// A tone is the fill, the edge, the ink of the mark, of the title and of the detail.
// A quiet tone lies on the panel level and differs only in the colour of its mark.
const quiet = (mark) => [LEVEL.panel.fill, 'outlineVariant', mark, 'onSurface', 'onSurfaceVariant'];
const NOTICE_TONES = {
  Secure: quiet('primary'), Open: quiet('tertiary'), Neutral: quiet('onSurfaceVariant'), Success: quiet('success'),
  Warning: ['warningContainer', null, 'onWarningContainer', 'onWarningContainer', 'onWarningContainer'],
  Error: ['errorContainer', null, 'onErrorContainer', 'onErrorContainer', 'onErrorContainer'],
};
/**
 * A message on a toned surface: mark, title, detail. The mark is as tall as the first line and stands beside it,
 * as far from the left edge as from the top one; one line of text leaves it as far from the bottom too.
 * A longer message runs on under the first line. The caller adds what the message ends with (banner.js has ending()). o: w, or max (as wide as its text, which runs on to the next line at max px), r, plain (a frame, not a component).
 */
function notice(name, Tone, glyph, title, detail, o = {}) {
  const [fill, edge, mark, ink, soft] = NOTICE_TONES[Tone];
  const n = box(name, { component: !o.plain, dir: 'H', gap: 3, pad: 4, w: o.w, r: o.r ?? 'large', fill, stroke: edge, align: 'MIN' });
  add(n, icon(glyph, mark)).name = 'mark';
  const col = add(n, box('text', { dir: 'V', gap: 1, align: 'MIN' }), { fillW: true });
  // Alone, the detail is the message: it takes the line height of the mark beside it.
  const lines = [title && para(col, title, 'titleSmall', ink, 'title'), detail && para(col, detail, title ? 'bodySmall' : 'bodyMedium', title ? soft : ink, 'detail')].filter(Boolean);
  if (!o.max) return n;
  const around = n.width - col.width;
  col.layoutSizingHorizontal = 'HUG';
  for (const line of lines) { line.textAutoResize = 'WIDTH_AND_HEIGHT'; line.layoutSizingHorizontal = 'HUG'; line.maxWidth = o.max - around; }
  return n;
}

// --- Screens to lay a surface over ---
const THREAD = [['Incoming', 'I booked the cabin near the lighthouse for two nights.'], ['Outgoing', 'Perfect. I will bring the camera and the thermos.'], ['Outgoing', 'Should we leave at 6 to beat the traffic?'], ['Incoming', 'Leo can drive. He has room for three and the gear.']];
// What a surface may have to lie over: each makes a screen of the given width and height.
const BACKDROPS = {
  Conversation: (Device, w, h) => {
    const f = surface('Conversation', 'background', { dir: 'V', w, h, clip: true, align: 'MIN' });
    add(f, inst('Top bar', { Kind: 'Private chat', Device }), { fillW: true });
    const feed = add(f, box('feed', { dir: 'V', gap: 1, pad: [3, feedPad(Device)], align: 'MIN' }), { fillW: true });
    for (const [side, Text] of THREAD) add(add(feed, box('place', { dir: 'H', justify: side === 'Outgoing' ? 'MAX' : 'MIN' }), { fillW: true }), setProps(inst(side + ' message', { Position: 'Single', Device, State: 'Default' }), { Text }));
    return f;
  },
  'Chat list': (Device, w, h) => {
    const f = surface('Chat list', 'panel', { dir: 'V', gap: 1, pad: [4, 2], w, h, clip: true });
    for (const State of ['Default', 'Selected', 'Default', 'Default', 'Default']) add(f, inst('Chat row', { State, Device }), { fillW: true });
    return f;
  },
  Settings: (Device, w, h) => {
    const f = surface('Settings', 'background', { dir: 'V', gap: 3, pad: 5, w, h, clip: true });
    for (const Kind of ['Switch and details', 'Control']) add(f, inst('Settings card', { Kind, Device }), { fillW: true });
    return f;
  },
  'Media viewer': (Device, w, h) => {
    const v = inst('Media viewer', { Kind: 'Image', Device });
    v.resize(w, h);
    const f = box('Media viewer', { dir: 'V', w, h, clip: true });
    add(f, v);
    return f;
  },
};
/** Lays [node] over [screen]: in its middle, or along its top or bottom edge. */
function over(screen, node, at = 'middle') {
  screen.appendChild(node);
  node.layoutPositioning = 'ABSOLUTE';
  if (at === 'bottom') node.resize(screen.width, node.height);
  node.x = (screen.width - node.width) / 2;
  node.y = at === 'bottom' ? screen.height - node.height : at === 'top' ? 16 : (screen.height - node.height) / 2;
  return screen;
}
