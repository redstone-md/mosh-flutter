// The call while the chats are in use: CallModalCard in its compact form (the
// bar) and FloatingCallView (the video tile that MainWindowCallFrame lets the
// user drag), with the screens they lie over.
card('Call bar and floating video', 'A call that is not open stays in sight as a bar across the top of the window, under the title bar, and on the phone above the conversation. It is the call window folded to a strip: the same lowest tone, the same buttons, and a press on the name opens the call again. On the desktop a call rings in the bar, so it can be answered without leaving the chat. A call with video folds to a tile instead, which shows the picture, can be moved to any corner and opens the call when pressed.');

const MIC = ['mic'], END = CALL_END;
// Per state: the line under the name, its colour, and the buttons.
const BARS = {
  Incoming: ['Incoming voice call', 'onSurfaceVariant', [END, ['call', 'Accept']]],
  Outgoing: ['Calling…', 'onSurfaceVariant', [MIC, END]],
  Voice: ['4:12', 'onSurfaceVariant', [MIC, END]],
  Muted: ['4:12, muted', 'onSurfaceVariant', [['mic_off', 'Lit'], END]],
  Reconnecting: ['4:12, reconnecting…', 'onSurfaceVariant', [MIC, END]],
  Warning: ['Microphone unavailable', 'warning', [['mic_off', 'Neutral', 'Disabled'], END]],
};
function callBar({ State, Device }) {
  const [status, ink, buttons] = BARS[State], phone = Device === 'Phone';
  const b = box('Call bar', { component: true, dir: 'H', gap: phone ? 2 : 3, pad: [1, phone ? 2 : 3, 1, phone ? 3 : 4], w: FEED[Device], fill: BENEATH });
  avatarSlot(b, { Size: 'Compact' });
  const col = add(b, box('who', { dir: 'V', align: 'MIN' }), { fillW: true });
  add(col, text('Maya Chen', 'titleSmall', 'onSurface', { name: 'name', truncate: true }), { fillW: true });
  add(col, text(status, 'bodySmall', ink, { name: 'status', truncate: true }), { fillW: true });
  add(b, action('call_expand', Device)).name = 'expand';
  for (const [glyph, Tone, pressable] of buttons) add(b, callAction(glyph, { Tone, State: pressable })).name = glyph;
  return b;
}
const bars = display(await grid('Call bar', axis('State', Object.keys(BARS)), DEVICES, callBar));
prop(bars, 'Name', 'TEXT', 'Maya Chen', 'name');

const TILE = { Desktop: 320, Phone: 196 };
function floating({ Kind, Device }) {
  const w = TILE[Device], desktop = Device === 'Desktop';
  const t = surface('Floating call', 'popup', { component: true, dir: 'V', w, clip: true });
  const stage = add(t, inst('Call video stage', { Kind }));
  stage.name = 'stage';
  stage.resize(w, Math.round(w * 9 / 16));
  const foot = add(t, box('foot', { dir: 'H', gap: 1, pad: [1, 1, 1, 3] }), { fillW: true });
  add(foot, text('Maya Chen', 'labelLarge', 'onSurface', { name: 'name', truncate: true }), { fillW: true });
  // The phone's tile is too narrow for two buttons: a press on the picture opens the call there.
  if (desktop) add(foot, action('call_expand', Device)).name = 'expand';
  const end = add(foot, action('call_end', Device, { Kind: 'Tonal', ink: 'onError' }));
  end.name = 'end'; end.fills = paint('error');
  return t;
}
const tiles = display(await grid('Floating call', axis('Kind', ['Remote video', 'Two-way video', 'Waiting for video']), DEVICES, floating));
prop(tiles, 'Name', 'TEXT', 'Maya Chen', 'name');

const SCREEN = { Desktop: [FEED.Desktop, 460], Phone: [PHONE_SCREEN, 560] };
/** A screen ([under]: a key of BACKDROPS) with the call bar of [State] above it and, on the desktop, the title bar above both. */
function screen(Device, State, under = 'Conversation') {
  const [w, h] = SCREEN[Device];
  const f = surface(`${State ?? 'No bar'} · ${Device}`, 'background', { dir: 'V', w, h, clip: true });
  if (Device === 'Desktop') add(f, inst('Window title bar', { Kind: 'With state' }), { fillW: true });
  if (State) add(f, inst('Call bar', { State, Device }), { fillW: true });
  add(f, BACKDROPS[under](Device, w, h), { fillW: true, fillH: true });
  return f;
}
/** Lays [node] in the upper right corner of [frame], where the tile starts out. */
function corner(frame, node, top) {
  add(frame, node, { abs: [frame.width - node.width - 12, top] });
  return frame;
}
await examples('The bar over a conversation: a call in progress, and a call ringing on the desktop', [screen('Desktop', 'Voice'), screen('Phone', 'Muted'), screen('Desktop', 'Incoming')], 'MIN');
await examples('The bar over the chat list', [screen('Phone', 'Voice', 'Chat list')], 'MIN');
await examples('The video tile over a conversation', [
  corner(screen('Desktop', null), inst('Floating call', { Kind: 'Two-way video', Device: 'Desktop' }), 52),
  corner(screen('Phone', null), inst('Floating call', { Kind: 'Remote video', Device: 'Phone' }), 12),
], 'MIN');
/** The toast that answers a second call: under the bars at the top of the window, and above the phone's bottom edge. */
function busy(Device) {
  const toast = setProps(inst('Toast', { Tone: 'Error', Device }), { 'Message, error': 'Finish the current call before starting another one' });
  const f = screen(Device, 'Voice'), bars = f.children.slice(0, -1).reduce((h, bar) => h + bar.height, 0), M = px('space/4');
  over(f, toast, 'top');
  toast.y = Device === 'Phone' ? f.height - toast.height - M : bars + M;
  return f;
}
await examples('Starting a second call', [busy('Desktop'), busy('Phone')], 'MIN');
