// Plugin-side helpers for the surface cards (dialog and after): build.mjs
// prepends this file after lib.js. A surface takes its colour, edge and shadow
// from its level here, never from a colour picked where it is drawn.

// The four levels a surface can sit on, lowest first. The background is the
// screen itself; a panel is a part of the screen (the chat list, the title bar,
// a card of settings); a popup floats over the screen until its choice is made
// (menu, toast); a modal stops the screen and always lies on the scrim.
// Popup and modal share a tone: the edge and the shadow lift both off whatever
// is under them, and the scrim alone says that the screen is stopped.
const LEVEL = {
  background: { fill: 'surface' },
  panel: { fill: 'surfaceContainerLow' },
  popup: { fill: 'surfaceContainerHigh', stroke: 'outlineVariant', effect: 'elevation2' },
  modal: { fill: 'surfaceContainerHigh', stroke: 'outlineVariant', effect: 'elevation3' },
};
/** A box on one of the LEVELs; o as for box(). */
const surface = (name, level, o = {}) => box(name, { ...(LEVEL[level] ?? fail('level ' + level)), ...o });
/** A panel drawn as a card inside the background: the panel's tone with a quiet edge. */
const cardSurface = (name, o = {}) => surface(name, 'panel', { stroke: 'outlineVariant', r: 'extraLarge', ...o });

/** A Button by its label. o: Kind, State, glyph (shows the leading icon). */
function button(Device, Label, { Kind = 'Primary', State = 'Default', glyph } = {}) {
  return setProps(inst('Button', { Kind, Device, State }), glyph ? { Label, Icon: true, 'Icon glyph': ICONS[glyph] ?? fail('Icon/' + glyph) } : { Label });
}
const textButton = (Device, Label, glyph) => button(Device, Label, { Kind: 'Text', glyph });
/** A Button turned destructive: the error colour takes the place of the primary one. */
function danger(Device, Label, glyph) {
  const b = button(Device, Label, { glyph });
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
// Widths of a dialog and of the phone's screen, which a sheet spans.
const DIALOG = { Desktop: 400, Phone: 326 }, SCREEN = { Desktop: 1280, Phone: 390 };
