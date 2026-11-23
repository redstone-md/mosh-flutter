// The call opened to the whole window or screen: CallModalCard as it stands
// alone, with the backdrop and the full-screen button that MainWindowCallHost
// draws around it today. The redesign makes them one component.
card('Call window', 'An open call takes the whole window, on the lowest tone, like the media viewer. A voice call puts the person in the middle: who it is and how the call is going. With video the picture takes that place and grows as far as the window lets it without being cut, so a phone turned on its side gives it the whole screen; the name and the time move to a plate in the corner. The buttons stay on their dock at the bottom in every state, and a warning sits just above them, where the button it is about is. While the other side’s video is showing, everything laid over it but your own camera leaves after three seconds without a pointer move, a touch or a key, and any of those brings it back. It stays while the call is voice only, ringing or waiting for video, while a warning is shown, while the keyboard’s focus is on a button and while the pointer is over the dock. A muted microphone keeps a mark in the corner when the rest is gone, so being unheard is never hidden.');

const VIEW = { Desktop: [720, 460], Phone: [390, 640], 'Phone on its side': [844, 390] };
const TALK = [['mic'], ['video_off'], ['tune'], CALL_END];
/** TALK with the button of [glyph] replaced by [button]. */
const talk = (glyph, button) => TALK.map((b) => (b[0] === glyph ? button : b));
// Per state: the line under the name, the video stage, the dock's buttons, a notice [tone, text], and what an idle call keeps over its video:
// 'nothing', or 'muted' for the mark of a muted microphone. The rules of leaving are in the card's note above.
const STATES = {
  Incoming: ['Incoming voice call', null, [CALL_END, ['call', 'Accept']]],
  'Waiting for confirmation': ['Waiting for confirmation…', null, TALK],
  Outgoing: ['Calling…', null, TALK],
  'Connecting audio': ['0:02, connecting audio…', null, TALK],
  Voice: ['4:12', null, TALK],
  Muted: ['4:12', null, talk('mic', ['mic_off', 'Lit'])],
  Reconnecting: ['4:12, reconnecting…', null, TALK],
  'Microphone unavailable': ['4:12', null, talk('mic', ['mic_off', 'Neutral', 'Disabled']), ['Warning', 'Microphone unavailable. You can still listen.']],
  'Camera unavailable': ['4:12', null, talk('video_off', ['video_off', 'Neutral', 'Disabled']), ['Warning', 'Camera unavailable. Voice remains available.']],
  'Audio failed': ['Audio unavailable', null, [['mic', 'Neutral', 'Disabled'], CALL_END], ['Error', 'Microphone is in use by another app']],
  'Calls on another device': ['4:12', null, TALK, ['Warning', 'Calls are active on different devices. New calls are unavailable until they end.']],
  'Waiting for video': ['4:12', 'Waiting for video', TALK],
  'Remote video': ['4:12', 'Remote video', TALK],
  'Camera preview': ['4:12', 'Camera preview', talk('video_off', ['video', 'Lit'])],
  'Two-way video': ['4:12', 'Two-way video', talk('video_off', ['video', 'Lit'])],
  'Controls hidden': ['4:12', 'Two-way video', [], null, 'nothing'],
  'Controls hidden and muted': ['4:12', 'Two-way video', [], null, 'muted'],
};
/** The largest 16:9 stage that fits the window whole, in its middle. It grows with an instance that is made larger in the same proportion; a window of another shape wants its stage fitted again. */
function fitStage(win, Kind) {
  const s = inst('Call video stage', { Kind }), w = Math.min(win.width, Math.round(win.height * 16 / 9)), h = Math.round(w * 9 / 16);
  s.name = 'stage';
  s.resize(w, h);
  add(win, s, { abs: [(win.width - w) / 2, (win.height - h) / 2] });
  s.constraints = { horizontal: 'SCALE', vertical: 'SCALE' };
}
/** Over video the name and the line under it sit on a plate, as every button does. */
function whoPlate(status, device) {
  const p = box('who plate', { dir: 'H', gap: 2, pad: [0, 4], hk: controlHeight(device), r: 'full', fill: CALL_TONES.Neutral[0] });
  add(p, text('Maya Chen', 'titleSmall', 'onSurface', { name: 'name' }));
  add(p, text(status, 'bodySmall', 'onSurfaceVariant', { name: 'status' }));
  return p;
}
/** A warning [tone, text] above the dock: as wide as its text, which runs on to a second line at [max] px. */
function callNotice([Tone, message], max) {
  const n = notice('notice', Tone, Tone === 'Error' ? 'error' : 'warning', null, message, { plain: true, r: 'largeIncreased' });
  const line = n.findOne((x) => x.type === 'TEXT'), around = n.width - line.width;
  line.textAutoResize = 'WIDTH_AND_HEIGHT';
  line.parent.layoutSizingHorizontal = line.layoutSizingHorizontal = 'HUG';
  line.maxWidth = max - around;
  return n;
}
/** The mark an idle call keeps while the microphone is muted: the muted button's plate, too small to be taken for a button. */
function mutedMark() {
  const m = box('muted', { dir: 'H', wk: 8, hk: 8, r: 'full', fill: CALL_TONES.Lit[0], justify: 'CENTER' });
  add(m, icon('mic_off', CALL_TONES.Lit[1], 4));
  return m;
}
/** The row along the top of [win]: the way out of the open call, the full screen button and, with video in the middle, who the call is with. over: the line a call over video shows beside the name. */
function topRow(win, touch, over, idle) {
  if (idle === 'nothing') return;
  const desktop = touch === 'Desktop';
  const top = add(win, box('top', { dir: 'H', pad: desktop ? 3 : 2, justify: 'SPACE_BETWEEN' }), { fillW: true });
  if (idle) return add(top, mutedMark());
  const lead = add(top, box('lead', { dir: 'H', gap: 2 }));
  add(lead, action('call_minimize', touch, { Kind: 'Tonal' })).name = 'minimize';
  if (over) add(lead, whoPlate(over, touch));
  // A phone's call already has the whole screen.
  if (desktop) add(top, action('fullscreen', touch, { Kind: 'Tonal' })).name = 'full screen';
}
function callWindow({ State, Device }) {
  const [status, video, buttons, warning, idle] = STATES[State], [w, h] = VIEW[Device];
  const desktop = Device === 'Desktop', upright = Device === 'Phone', touch = desktop ? 'Desktop' : 'Phone';
  const win = box('Call window', { component: true, dir: 'V', w, h, fill: BENEATH, clip: true });
  if (video) fitStage(win, video);
  topRow(win, touch, video && status, idle);
  // On its side the phone has no height to spare: the name goes beside the avatar, not under it.
  const flat = !desktop && !upright;
  const who = add(win, box('who', { dir: flat ? 'H' : 'V', gap: flat ? 4 : 3, pad: [0, 4], justify: 'CENTER' }), { fillW: true, fillH: true });
  if (!video) {
    avatarSlot(who, { Size: 'Large' });
    const lines = add(who, box('lines', { dir: 'V', gap: 1, align: flat ? 'MIN' : 'CENTER' }), { fillW: !flat });
    for (const [chars, slot, ink, name] of [['Maya Chen', upright ? 'headlineSmall' : 'headlineMedium', 'onSurface', 'name'], [status, 'bodyLarge', State === 'Audio failed' ? 'error' : 'onSurfaceVariant', 'status']]) {
      const line = add(lines, text(chars, slot, ink, flat ? { name } : { name, truncate: true }), { fillW: !flat });
      if (!flat) line.textAlignHorizontal = 'CENTER';
    }
  }
  if (idle) return win;
  const foot = add(win, box('foot', { dir: 'V', gap: 3, pad: [0, 4, upright ? 8 : 5, 4] }), { fillW: true });
  if (warning) add(foot, callNotice(warning, Math.min(w - px('space/4') * 2, DIALOG.Desktop)));
  add(foot, callDock(buttons, upright ? 'Large' : 'Regular'));
  return win;
}
const windows = display(await grid('Call window', axis('State', Object.keys(STATES)), axis('Device', Object.keys(VIEW)), callWindow));
prop(windows, 'Name', 'TEXT', 'Maya Chen', 'name');

/** A call window with the device dialog over it; its lists are the Select of the base controls. open: the microphone's list is open, a menu on the desktop and a sheet on the phone. */
function devices(Device, open) {
  const win = inst('Call window', { State: 'Camera preview', Device });
  const f = box(`Devices · ${Device}${open ? ', microphone' : ''}`, { dir: 'V', w: win.width, h: win.height, clip: true });
  add(f, win);
  dim(f);
  const d = inst('Dialog', { Kind: 'Devices', Device });
  over(f, d);
  if (!open) return f;
  if (Device === 'Phone') { dim(f); return over(f, inst('Sheet', { Kind: 'Microphone' }), 'bottom'); }
  const select = d.findOne((n) => n.type === 'INSTANCE' && n.name === 'Select');
  select.swapComponent(variant('Select', { State: 'Open', Device }));
  const at = select.absoluteBoundingBox, origin = f.absoluteBoundingBox;
  add(f, inst('Select menu'), { abs: [at.x - origin.x, at.y - origin.y + at.height + px('space/1')] });
  return f;
}
await examples('Call devices: the dialog over the call, and the microphone being chosen', [devices('Desktop'), devices('Desktop', true), devices('Phone'), devices('Phone', true)], 'MIN');
