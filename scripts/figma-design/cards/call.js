// The call opened to the whole window or screen: CallModalCard as it stands
// alone, with the backdrop and the full-screen button that MainWindowCallHost
// draws around it today. The redesign makes them one component.
card('Call window', 'An open call takes the whole window, on the lowest tone, like the media viewer. A voice call puts the person in the middle: who it is and how the call is going. With video the picture takes that place and grows as far as the window lets it without being cut, so a phone turned on its side gives it the whole screen; the name and the time move to a plate in the corner. The buttons stay on their dock at the bottom in every state, and a warning sits just above them, where the button it is about is.');

const VIEW = { Desktop: [720, 460], Phone: [390, 640], 'Phone on its side': [640, 390] };
const TALK = [['mic'], ['video_off'], ['tune'], ['call_end', 'End']];
/** TALK with the button of [glyph] replaced by [button]. */
const talk = (glyph, button) => TALK.map((b) => (b[0] === glyph ? button : b));
// Per state: the line under the name, the video stage, the dock's buttons and a notice [tone, text].
const STATES = {
  Incoming: ['Incoming voice call', null, [['call_end', 'End'], ['call', 'Accept']]],
  'Waiting for confirmation': ['Waiting for confirmation…', null, [['mic', 'Neutral', 'Disabled'], ['call_end', 'End']]],
  Outgoing: ['Calling…', null, [['mic'], ['video_off'], ['call_end', 'End']]],
  'Connecting audio': ['0:02, connecting audio…', null, talk('mic', ['mic', 'Neutral', 'Disabled'])],
  Voice: ['4:12', null, TALK],
  Muted: ['4:12', null, talk('mic', ['mic_off', 'Lit'])],
  Reconnecting: ['4:12, reconnecting…', null, TALK],
  'Microphone unavailable': ['4:12', null, talk('mic', ['mic_off', 'Neutral', 'Disabled']), ['Warning', 'Microphone unavailable. You can still listen.']],
  'Camera unavailable': ['4:12', null, talk('video_off', ['video_off', 'Neutral', 'Disabled']), ['Warning', 'Camera unavailable. Voice remains available.']],
  'Audio failed': ['Audio unavailable', null, [['mic', 'Neutral', 'Disabled'], ['call_end', 'End']], ['Error', 'Microphone is in use by another app']],
  'Calls on another device': ['4:12', null, TALK, ['Warning', 'Calls are active on different devices. New calls are unavailable until they end.']],
  'Waiting for video': ['4:12', 'Waiting for video', TALK],
  'Remote video': ['4:12', 'Remote video', TALK],
  'Camera preview': ['4:12', 'Camera preview', talk('video_off', ['video', 'Lit'])],
  'Two-way video': ['4:12', 'Two-way video', talk('video_off', ['video', 'Lit'])],
};
/** The largest 16:9 stage that fits the window whole, in its middle. */
function fitStage(window, Kind) {
  const s = inst('Call video stage', { Kind }), w = Math.min(window.width, Math.round(window.height * 16 / 9)), h = Math.round(w * 9 / 16);
  s.name = 'stage';
  s.resize(w, h);
  add(window, s, { abs: [(window.width - w) / 2, (window.height - h) / 2] });
  s.constraints = { horizontal: 'CENTER', vertical: 'CENTER' };
}
/** Over video the name and the line under it sit on a plate, as every button does. */
function whoPlate(status, tall) {
  const p = box('who', { dir: 'H', gap: 2, pad: [0, 4], hk: tall ? 12 : 10, r: 'full', fill: 'surfaceContainerHighest' });
  add(p, text('Maya Chen', 'titleSmall', 'onSurface', { name: 'name' }));
  add(p, text(status, 'bodySmall', 'onSurfaceVariant', { name: 'status' }));
  return p;
}
function callWindow({ State, Device }) {
  const [status, video, buttons, warning] = STATES[State], [w, h] = VIEW[Device];
  const desktop = Device === 'Desktop', upright = Device === 'Phone', touch = desktop ? 'Desktop' : 'Phone';
  const win = box('Call window', { component: true, dir: 'V', w, h, fill: BENEATH, clip: true });
  if (video) fitStage(win, video);
  const top = add(win, box('top', { dir: 'H', gap: 2, pad: desktop ? 3 : 2 }), { fillW: true });
  add(top, action('call_minimize', touch, { Kind: 'Tonal' })).name = 'minimize';
  if (video) add(top, whoPlate(status, !desktop));
  add(top, box('room', { dir: 'H' }), { fillW: true });
  // A phone's call already has the whole screen.
  if (desktop) add(top, action('fullscreen', touch, { Kind: 'Tonal' })).name = 'full screen';
  const who = add(win, box('who', { dir: 'V', gap: 1, pad: [0, 4], justify: 'CENTER' }), { fillW: true, fillH: true });
  if (!video) {
    avatarSlot(who, { Size: 'Large' });
    add(who, box('gap', { dir: 'H', hk: 2 }));
    add(who, text('Maya Chen', upright ? 'headlineSmall' : 'headlineMedium', 'onSurface', { name: 'name', truncate: true }), { fillW: true }).textAlignHorizontal = 'CENTER';
    add(who, text(status, 'bodyLarge', State === 'Audio failed' ? 'error' : 'onSurfaceVariant', { name: 'status', truncate: true }), { fillW: true }).textAlignHorizontal = 'CENTER';
  }
  const foot = add(win, box('foot', { dir: 'V', gap: 3, pad: [0, 4, upright ? 8 : 5, 4] }), { fillW: true });
  if (warning) add(foot, notice('notice', warning[0], warning[0] === 'Error' ? 'error' : 'warning', null, warning[1], { plain: true, w: Math.min(w - px('space/4') * 2, DIALOG.Desktop), r: 'largeIncreased' }));
  add(foot, callDock(buttons, upright ? 'Large' : 'Regular'));
  return win;
}
const windows = display(await grid('Call window', axis('State', Object.keys(STATES)), axis('Device', Object.keys(VIEW)), callWindow));
prop(windows, 'Name', 'TEXT', 'Maya Chen', 'name');

/** A call window with the device dialog over it; its lists are the Select of the base controls. */
function devices(Device) {
  const win = inst('Call window', { State: 'Camera preview', Device });
  const f = box(`Devices · ${Device}`, { dir: 'V', w: win.width, h: win.height, clip: true });
  add(f, win);
  dim(f);
  const d = inst('Dialog', { Kind: 'Devices', Device });
  add(f, d, { abs: [(f.width - d.width) / 2, (f.height - d.height) / 2] });
  return f;
}
await examples('Call devices: the dialog over the call', [devices('Desktop'), devices('Phone')], 'MIN');
