// The call while the chats are in use: what replaces CallModalCard's compact
// strip, and FloatingCallView (the video tile that MainWindowCallFrame lets
// the user drag), with the screens they lie over.
card('Minimized call', 'A call that is not open stays in sight without moving the screen. On the desktop it is a plate in the title bar: who the call is with, how long it has run, the microphone and the red button. A press on the name opens the call again; the two buttons do their own work and open nothing. A call rings in a card in the upper corner, so it can be answered without leaving the chat. The phone has no title bar, so the call is a strip above the conversation with the same parts. A call with video folds to a tile instead, which shows the picture, can be moved to any corner and opens the call when pressed.');

// Per state: the line beside the name, its colour, and the microphone as [glyph, lit, off].
const STATES = {
  Outgoing: ['Calling…', 'onSurfaceVariant', ['mic']],
  Voice: ['4:12', 'onSurfaceVariant', ['mic']],
  Muted: ['4:12, muted', 'onSurfaceVariant', ['mic_off', true]],
  Reconnecting: ['4:12, reconnecting…', 'onSurfaceVariant', ['mic']],
  Warning: ['Microphone unavailable', 'warning', ['mic_off', false, true]],
};
/** A button of the plate: a small round one, on a plate of [fill] or on none. */
function small(glyph, fill, ink) {
  const b = box(glyph, { dir: 'H', wk: 6, hk: 6, r: 'full', fill, justify: 'CENTER' });
  add(b, icon(glyph, ink, 4));
  return b;
}
/** The name and the line beside it, standing on one baseline. wide: the phone's strip, where the line is cut to the room it has. */
function who(status, ink, wide) {
  const w = box('who', { dir: 'H', gap: 2, align: 'BASELINE' });
  add(w, text('Maya Chen', wide ? 'titleSmall' : 'labelLarge', 'onSurface', { name: 'name' }));
  add(w, text(status, wide ? 'bodySmall' : 'labelMedium', ink, { name: 'status', truncate: wide }), { fillW: wide });
  return w;
}
const plates = display(await grid('Call plate', axis('State', Object.keys(STATES)), [['Desktop', {}]], ({ State }) => {
  const [status, ink, [glyph, lit, off]] = STATES[State];
  const p = box('Call plate', { component: true, dir: 'H', gap: 2, pad: [0, 1, 0, 3], hk: 8, r: 'full', fill: CALL_TONES.Neutral[0] });
  add(p, who(status, ink, false));
  const mic = add(p, small(glyph, lit ? CALL_TONES.Lit[0] : null, lit ? CALL_TONES.Lit[1] : 'onSurface'));
  if (off) disable(mic, [mic.children[0]]);
  add(p, small('call_end', ...CALL_TONES.End));
  return p;
}));
prop(plates, 'Name', 'TEXT', 'Maya Chen', 'name');

const ringing = display(await grid('Incoming call card', ONE, [['Desktop', {}]], () => {
  const c = surface('Incoming call card', 'popup', { component: true, dir: 'V', gap: 4, pad: 4, w: 320, align: 'MIN' });
  const head = add(c, box('who', { dir: 'H', gap: 3 }), { fillW: true });
  avatarSlot(head, { Size: 'Medium' });
  const lines = add(head, box('lines', { dir: 'V', align: 'MIN' }), { fillW: true });
  add(lines, text('Maya Chen', 'titleMedium', 'onSurface', { name: 'name', truncate: true }), { fillW: true });
  add(lines, text('Incoming voice call', 'bodySmall', 'onSurfaceVariant', { name: 'status' }));
  const answers = add(c, box('answers', { dir: 'H', gap: 2 }), { fillW: true });
  add(answers, danger('Desktop', 'Decline', 'call_end'), { fillW: true });
  add(answers, labelButton('Desktop', 'Accept', { glyph: 'call' }), { fillW: true });
  return c;
}));
prop(ringing, 'Name', 'TEXT', 'Maya Chen', 'name');

/** An Icon button on a plate of a call tone: the phone's strip and the video tile are too small for the call's own buttons. */
function toned(glyph, Device, Tone) {
  const b = action(glyph, Device, { Kind: 'Tonal', ink: CALL_TONES[Tone][1] });
  b.fills = paint(CALL_TONES[Tone][0]);
  return b;
}
// The phone can be rung in its strip too: a call that was minimized before it was answered.
const STRIPS = { Incoming: ['Incoming voice call', 'onSurfaceVariant', null], ...STATES };
const strips = display(await grid('Call strip', axis('State', Object.keys(STRIPS)), [['Phone', {}]], ({ State }) => {
  const [status, ink, mic] = STRIPS[State];
  const s = box('Call strip', { component: true, dir: 'H', gap: 2, pad: [1, 2, 1, 4], w: PHONE_SCREEN, fill: BENEATH });
  add(s, who(status, ink, true), { fillW: true });
  if (mic) {
    const [glyph, lit, off] = mic;
    add(s, lit ? toned(glyph, 'Phone', 'Lit') : action(glyph, 'Phone', { State: off ? 'Disabled' : 'Default' })).name = 'microphone';
  }
  add(s, toned('call_end', 'Phone', 'End')).name = 'end';
  if (!mic) add(s, toned('call', 'Phone', 'Accept')).name = 'accept';
  return s;
}));
prop(strips, 'Name', 'TEXT', 'Maya Chen', 'name');

const TILE = { Desktop: 320, Phone: 196 };
function floating({ Kind, Device }) {
  const w = TILE[Device];
  const t = surface('Floating call', 'popup', { component: true, dir: 'V', w, clip: true });
  const stage = add(t, inst('Call video stage', { Kind }));
  stage.name = 'stage';
  stage.resize(w, Math.round(w * 9 / 16));
  const foot = add(t, box('foot', { dir: 'H', gap: 1, pad: [1, 1, 1, 3] }), { fillW: true });
  add(foot, text('Maya Chen', 'labelLarge', 'onSurface', { name: 'name', truncate: true }), { fillW: true });
  // The phone's tile is too narrow for two buttons: a press on the picture opens the call there.
  if (Device === 'Desktop') add(foot, action('call_expand', Device)).name = 'expand';
  add(foot, toned('call_end', Device, 'End')).name = 'end';
  return t;
}
const tiles = display(await grid('Floating call', axis('Kind', ['Remote video', 'Two-way video', 'Waiting for video']), DEVICES, floating));
prop(tiles, 'Name', 'TEXT', 'Maya Chen', 'name');

const SCREEN = { Desktop: [FEED.Desktop, 460], Phone: [PHONE_SCREEN, 560] }, EDGE = 12;
/** A screen ([under]: a key of BACKDROPS) with the call of [State] in the title bar on the desktop, and in the strip above it on the phone. */
function screen(Device, State, under = 'Conversation') {
  const [w, h] = SCREEN[Device], desktop = Device === 'Desktop';
  const f = surface(`${State ?? 'No call'} · ${Device}`, 'background', { dir: 'V', w, h, clip: true });
  const bar = desktop && add(f, inst('Window title bar', { Kind: 'With state' }), { fillW: true });
  if (State && !desktop) add(f, inst('Call strip', { State }), { fillW: true });
  add(f, BACKDROPS[under](Device, w, h), { fillW: true, fillH: true });
  if (State && desktop) {
    // The plate stands beside the state pill, in the room the title bar leaves for dragging the window.
    const plate = inst('Call plate', { State }), pill = bar.children.at(-1);
    add(f, plate, { abs: [pill.x - plate.width - px('space/2'), (bar.height - plate.height) / 2] });
  }
  return f;
}
/** Lays [node] in the upper right corner of [frame], under the title bar where there is one. */
function corner(frame, node) {
  const bar = frame.children[0].type === 'INSTANCE' ? frame.children[0].height : 0;
  add(frame, node, { abs: [frame.width - node.width - EDGE, bar + EDGE] });
  return frame;
}
await examples('A call in the title bar, a call ringing, and the strip on the phone', [screen('Desktop', 'Voice'), corner(screen('Desktop', null), inst('Incoming call card')), screen('Phone', 'Muted'), screen('Phone', 'Voice', 'Chat list')], 'MIN');
await examples('The video tile over a conversation', [
  corner(screen('Desktop', null), inst('Floating call', { Kind: 'Two-way video', Device: 'Desktop' })),
  corner(screen('Phone', null), inst('Floating call', { Kind: 'Remote video', Device: 'Phone' })),
], 'MIN');
/** The toast that answers a second call: under the title bar, and above the phone's bottom edge. */
function busy(Device) {
  const toast = setProps(inst('Toast', { Tone: 'Error', Device }), { 'Message, error': 'Finish the current call before starting another one' });
  const f = over(screen(Device, 'Voice'), toast, 'top'), M = px('space/4');
  toast.y = Device === 'Phone' ? f.height - toast.height - M : f.children[0].height + M;
  return f;
}
await examples('Starting a second call', [busy('Desktop'), busy('Phone')], 'MIN');
