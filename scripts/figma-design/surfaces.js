// Plugin-side helpers shared by the search card and the surface cards (dialog
// and after): build.mjs prepends this file after lib.js. A surface takes its
// colour, edge, corners and shadow from its level here. The tones under and
// inside the levels (BENEATH, inset, plate) are named here too, so no card
// picks a surface colour of its own.

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
// Under every level: the scrim, and the stage of the media viewer, which wants nothing brighter than the picture.
const BENEATH = 'surfaceContainerLowest';
/** A box on one of the LEVELs; o as for box(). */
const surface = (name, level, o = {}) => box(name, { ...(LEVEL[level] ?? fail('level ' + level)), ...o });
/** A panel drawn as a card inside the background: the panel's tone with a quiet edge. */
const cardSurface = (name, o = {}) => surface(name, 'panel', { stroke: 'outlineVariant', r: 'extraLarge', ...o });
/** Padding of a card, as a space key. */
const cardPad = (Device) => (Device === 'Phone' ? 4 : 5);
/** A plate set into a card to hold one thing apart (a device, a code): a tone up, with corners concentric to the card's. */
const inset = (name, o = {}) => box(name, { fill: 'surfaceContainer', r: 'small', ...o });
/** The Icon/<name> component. */
const glyphOf = (name) => ICONS[name] ?? fail('Icon/' + name);

/** The plate with the icon of a card's subject; a toned banner gives it its own fill and ink. */
function plate(glyph, fill = 'surfaceContainerHighest', ink = 'primary') {
  const p = box('plate', { dir: 'H', wk: 10, hk: 10, r: 'medium', fill, justify: 'CENTER' });
  add(p, icon(glyph, ink));
  return p;
}
/** The header of a card: plate, title, a line about it and, at the right, [tail]. */
function header(parent, glyph, title, line, tail) {
  const h = add(parent, box('header', { dir: 'H', gap: 3 }), { fillW: true });
  add(h, plate(glyph));
  const col = add(h, box('text', { dir: 'V', align: 'MIN' }), { fillW: true });
  para(col, title, 'titleMedium', 'onSurface', 'title');
  if (line) para(col, line, 'bodySmall', 'onSurfaceVariant', 'line');
  if (tail) add(h, tail);
  return h;
}
/** A Button by its label (button() is the Button card's own builder). o: Kind, State, glyph (shows the leading icon). */
function labelButton(Device, Label, { Kind = 'Primary', State = 'Default', glyph } = {}) {
  return setProps(inst('Button', { Kind, Device, State }), glyph ? { Label, Icon: true, 'Icon glyph': glyphOf(glyph) } : { Label });
}
const textButton = (Device, Label, glyph) => labelButton(Device, Label, { Kind: 'Text', glyph });
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
