// The window's title bar on the desktop (MoshTitleBar with its chat list
// toggle and DesktopCaptionButtons) and the bar at the top of a conversation
// (ConversationAppBar, ConversationHeaderTitle, ChatHeaderMenu, MobileSearchToggle).
// The app today shows FingerprintLock beside the name. The redesign takes it out of the bar:
// checking the fingerprint becomes a row of the details panel (cards/details.js).
card('Title bar and top bar', 'The title bar belongs to the window: the app’s mark, a toggle for the chat list and whether Mosh is connected, on the panel level so it reads as part of the frame and not of the chat. The phone has no window, so it has no title bar. The top bar belongs to the conversation: who it is with, how it is connected, and what can be done with it. Private chats and groups are always end-to-end encrypted, so the bar does not say so beside every name. It names the exception: a public channel says in its line that it is not encrypted. Checking the fingerprint is in the details panel.');
function logo() {
  const m = box('logo', { dir: 'H', wk: 6, hk: 6, r: 'small', fill: 'primary', justify: 'CENTER' });
  add(m, text('M', 'labelLargeEmphasized', 'onPrimary'));
  return m;
}
/** The three buttons of a Windows window; they span the bar's height and have square corners, as the system draws them. */
function captionButtons() {
  const c = box('window buttons', { dir: 'H' });
  for (const glyph of ['minimize', 'maximize', 'close']) add(add(c, box(glyph, { dir: 'H', wk: 12, hk: 10, justify: 'CENTER' })), icon(glyph, 'onSurfaceVariant', 4));
  return c;
}
// Per kind: toggle, name, state pill (its size), window buttons, width.
const BARS = {
  'Name and list': [true, true, null, false, 720],
  'With state': [true, true, 'Full', false, 720],
  Onboarding: [false, false, null, false, 720],
  Windows: [true, true, 'Full', true, 720],
  Narrow: [true, false, 'Compact', false, 360],
};
display(await grid('Window title bar', axis('Kind', Object.keys(BARS)), [['Desktop', {}]], ({ Kind }) => {
  const [toggle, name, pill, buttons, w] = BARS[Kind];
  const b = surface('Window title bar', 'panel', { component: true, dir: 'H', gap: 2, pad: [0, buttons ? 0 : 3, 0, toggle ? 1 : 3], w, hk: 10 });
  if (toggle) add(b, action('list_toggle', 'Desktop')).name = 'chat list toggle';
  add(b, logo());
  if (name) add(b, text('Mosh', 'titleSmall', 'onSurface'));
  add(b, box('drag area', { dir: 'H' }), { fillW: true });
  if (pill) add(b, inst('State pill', { Size: pill, State: 'Ready' }));
  if (buttons) add(b, captionButtons());
  return b;
}));

// Per kind: avatar, name, the line under the name, and whether a call can be placed.
const TOPS = {
  'Private chat': [{ Kind: 'Person', Plate: '2' }, 'Maya Chen', 'Connected, direct', true],
  'Waiting for contact': [{ Kind: 'Person', Plate: '2' }, 'Maya Chen', 'Waiting for Maya to open the invite', false],
  'Status unknown': [{ Kind: 'Person', Plate: '2' }, 'Maya Chen', null, true],
  Group: [{ Kind: 'Group', Plate: '1' }, 'Weekend plans', 'Admin, 4 members, MLS ready', false],
  Channel: [{ Kind: 'Channel', Plate: '3' }, '#photography', 'Public channel, not encrypted', false],
};
function topBar({ Kind, Device }) {
  const [avatar, name, line, calls] = TOPS[Kind], phone = Device === 'Phone';
  const b = surface('Top bar', 'background', { component: true, dir: 'H', gap: phone ? 2 : 3, pad: [2, phone ? 1 : feedPad(Device)], w: FEED[Device], minHk: 16 });
  if (phone) add(b, action('back', Device)).name = 'back';
  avatarSlot(b, { ...avatar, Size: phone ? 'Small' : 'Medium' });
  const col = add(b, box('title', { dir: 'V', align: 'MIN' }), { fillW: true });
  add(col, text(name, 'titleMedium', 'onSurface', { name: 'name', truncate: true }), { fillW: true });
  if (line) add(col, text(line, 'bodySmall', 'onSurfaceVariant', { name: 'status', truncate: true }), { fillW: true });
  const actions = add(b, box('actions', { dir: 'H' }));
  if (calls) add(actions, action('call', Device)).name = 'call';
  add(actions, action('search', Device)).name = 'search';
  add(actions, action('more', Device)).name = 'menu';
  return b;
}
display(await grid('Top bar', axis('Kind', Object.keys(TOPS)), DEVICES, topBar));

/** A top bar with what it opens under it: [under] gets the frame to add to. */
function opened(label, Kind, Device, lit, under) {
  const f = surface(label, 'background', { dir: 'V', w: FEED[Device], align: 'MAX' });
  const bar = add(f, inst('Top bar', { Kind, Device }), { fillW: true });
  const b = bar.findOne((n) => n.name === lit);
  b.swapComponent(variant('Icon button', { Kind: 'Tonal', State: 'Default', Device }));
  under(f);
  return f;
}
const menuOpen = opened('Chat menu open', 'Group', 'Desktop', 'menu', (f) => add(add(f, box('place', { dir: 'H', pad: [0, 5, 5, 0] })), inst('Menu', { Kind: 'Group', Device: 'Desktop' })));
const searching = opened('Search on the phone', 'Private chat', 'Phone', 'search', (f) => add(f, inst('Conversation search', { State: 'Search', Device: 'Phone' }), { fillW: true }));
await examples('The chat menu open, and search open on the phone', [menuOpen, searching], 'MIN');
