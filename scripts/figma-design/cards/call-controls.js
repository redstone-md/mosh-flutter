// What a call is made of: CallButton and CallVideoStage. The stage is also
// all that Android's picture in picture shows (AndroidPipOverlay).
card('Call controls', 'A call has few buttons and each says what it does by its plate. The neutral plate is a setting as it stands in a plain voice call. The light plate marks what differs from one: a microphone that is muted, a camera that is on. Saffron answers, and red is kept for the one button that ends the call. The buttons always stand together on a dock of their own, so the red one is never laid on the video itself and reads the same over any picture. The video is as large as the window or the screen lets it be without cutting it.');

// Per size: the button's edge and its glyph, as space keys. Large is for the phone held upright.
const SIZES = { Regular: [12, 6], Large: [16, 8] };
function callButton({ Tone, Size, State }) {
  const [plate, ink] = CALL_TONES[Tone], [edge, glyphKey] = SIZES[Size], off = State === 'Disabled';
  const b = box('Call button', { component: true, dir: 'H', wk: edge, hk: edge, r: 'full', clip: true, justify: 'CENTER', fill: off ? null : plate });
  const glyph = add(b, icon('call', off ? 'onSurface' : ink, glyphKey));
  if (off) disable(b, [glyph], true);
  interact(b, State, ink);
  return b;
}
const plates = Object.keys(CALL_TONES).flatMap((Tone) => Object.keys(SIZES).map((Size) => [`${Tone}, ${Size.toLowerCase()}`, { Tone, Size }]));
const buttons = await grid('Call button', plates, STATES5, callButton);
prop(buttons, 'Icon glyph', 'INSTANCE_SWAP', ICONS.call, 'icon');

/** A control with what it does under it; the name is the tooltip on the desktop and what a screen reader says. */
function named(label, control) {
  const col = box(label, { dir: 'V', gap: 2 });
  add(col, control);
  add(col, text(label, 'labelMedium', 'onSurfaceMuted'));
  return col;
}
const button = (label, glyph, o) => named(label, callAction(glyph, o));
await examples('The buttons of a call', [
  button('Accept', 'call', { Tone: 'Accept' }), button('Decline, end', 'call_end', { Tone: 'End' }),
  button('Microphone', 'mic'), button('Muted', 'mic_off', { Tone: 'Lit' }), button('No microphone', 'mic_off', { State: 'Disabled' }),
  button('Camera off', 'video_off'), button('Camera on', 'video', { Tone: 'Lit' }), button('Devices', 'tune'),
], 'MIN');
// What moves the call between its sizes is not a call button: it is the tonal Icon button, which has a plate of its own too.
const sized = (label, glyph) => named(label, action(glyph, 'Desktop', { Kind: 'Tonal' }));
await examples('Around the call: its sizes', [sized('Minimize', 'call_minimize'), sized('Expand', 'call_expand'), sized('Full screen', 'fullscreen'), sized('Leave full screen', 'fullscreen_exit')], 'MIN');

/** A plate that stands for a camera's picture, which a screen puts in its place. */
function picture(name, fill, ink, glyphKey) {
  const p = box(name, { dir: 'H', fill, justify: 'CENTER' });
  add(p, icon('person', ink, glyphKey));
  return p;
}
const STAGE = [480, 270];
// Per kind: what fills the stage, and whether your own camera sits in its corner.
const KINDS = {
  'Remote video': ['remote', false], 'Two-way video': ['remote', true], 'Camera preview': ['own', false],
  'Waiting for video': ['waiting', false], 'No video': ['nobody', false],
};
function stage({ Kind }) {
  const [shown, corner] = KINDS[Kind], [w, h] = STAGE;
  const s = box('Call video stage', { component: true, dir: 'V', gap: 3, w, h, fill: BENEATH, clip: true, justify: 'CENTER' });
  if (shown === 'remote') add(s, picture('picture', 'tertiaryContainer', 'onTertiaryContainer', 16), { fillW: true, fillH: true });
  if (shown === 'own') add(s, picture('your camera', 'secondaryContainer', 'onSecondaryContainer', 16), { fillW: true, fillH: true });
  if (shown === 'waiting' || shown === 'nobody') add(s, inst('Avatar', { Kind: 'Person', Plate: '2', Size: 'Large' }));
  if (shown === 'waiting') add(s, text('Waiting for video…', 'bodyMedium', 'onSurfaceVariant', { name: 'status' }));
  if (corner) {
    // A quarter of the stage's width, in its lower right corner; it keeps that share at any size.
    const own = picture('your camera', 'secondaryContainer', 'onSecondaryContainer', 6), M = px('space/2');
    own.resize(w / 4, h / 4); own.primaryAxisSizingMode = own.counterAxisSizingMode = 'FIXED';
    radius(own, 'small'); stroke(own, 'outlineVariant');
    add(s, own, { abs: [w - w / 4 - M, h - h / 4 - M] });
    own.constraints = { horizontal: 'SCALE', vertical: 'SCALE' };
  }
  return s;
}
display(await grid('Call video stage', axis('Kind', Object.keys(KINDS)), ONE, stage));

/** The dock over a picture of one flat colour: the worst a video can do to the buttons. */
function docked(fill) {
  const v = box('over ' + fill, { dir: 'V', w: 320, h: 140, fill, justify: 'CENTER' });
  radius(v, 'medium');
  add(v, callDock([['mic'], ['video', 'Lit'], ['tune'], CALL_END]));
  return v;
}
await examples('The dock over a red, a light, a saffron and a dark picture', ['error', 'inverseSurface', 'primary', BENEATH].map(docked));

const pip = inst('Call video stage', { Kind: 'Remote video' });
pip.resize(256, 144);
await examples('Android picture in picture: the stage alone', [pip]);
