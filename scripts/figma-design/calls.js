// Plugin-side helpers of the call cards (call-controls, call, call-mini):
// run.mjs prepends this file after surfaces.js. What a call's buttons look
// like and what the name of a call is set in are decided here, so the open
// call and the minimized one cannot drift apart.

// The four tones of a call button: its plate and its glyph. Lit marks what differs from a plain voice call: a muted microphone, a camera that is on.
const CALL_TONES = { Neutral: ['surfaceContainerHighest', 'onSurface'], Lit: ['inverseSurface', 'onInverseSurface'], Accept: ['primary', 'onPrimary'], End: ['error', 'onError'] };
// A button of a dock is [glyph, Tone, State]; this one ends the call wherever it stands.
const CALL_END = ['call_end', 'End'];
/** A Call button showing [glyph]. o: Tone, Size, State. */
function callAction(glyph, { Tone = 'Neutral', Size = 'Regular', State = 'Default' } = {}) {
  const b = setProps(inst('Call button', { Tone, Size, State }), { 'Icon glyph': glyphOf(glyph) });
  b.findOne((n) => n.name === 'glyph').fills = paint(State === 'Disabled' ? 'onSurface' : CALL_TONES[Tone][1]);
  return b;
}
/** The dock of a call: its buttons on a plate of their own, so none of them ever lies on the video itself. buttons: [glyph, Tone, State] each. */
function callDock(buttons, Size = 'Regular') {
  const d = surface('dock', 'popup', { dir: 'H', gap: Size === 'Large' ? 4 : 3, pad: 3, r: 'full' });
  for (const [glyph, Tone, State] of buttons) add(d, callAction(glyph, { Tone, Size, State })).name = glyph;
  return d;
}
/** A glyph on a small round plate of a call tone, or on none: a button where the call has no room for its own, and a mark where it has no button at all. edge: a space key. */
function callMark(glyph, Tone, edge = 6) {
  const [fill, ink] = Tone ? CALL_TONES[Tone] : [null, 'onSurface'];
  const m = box(glyph, { dir: 'H', wk: edge, hk: edge, r: 'full', fill, justify: 'CENTER' });
  add(m, icon(glyph, ink, 4));
  return m;
}
/** Who a call is with and the line about it, side by side on one baseline: on a plate over video, in the title bar and in the phone's strip. o: ink (the line's colour), wide (the strip's sizes; the line is cut to the room it has). */
function callWho(status, { ink = 'onSurfaceVariant', wide = false } = {}) {
  const w = box('who', { dir: 'H', gap: 2, align: 'BASELINE' });
  add(w, text('Maya Chen', wide ? 'titleSmall' : 'labelLarge', 'onSurface', { name: 'name' }));
  add(w, text(status, wide ? 'bodySmall' : 'labelMedium', ink, { name: 'status', truncate: wide }), { fillW: wide });
  return w;
}
