// Plugin-side helpers of the screens in screens/: screens.mjs appends this file
// to the prelude of run.mjs. A screen is a frame of the capture's size in the
// "Screens" section of the Redesign page, filled with instances of the
// components and the frames that lay them out, and with the capture's data, so
// it can be put beside its frame on the "current" pages.
const SIZE = { Desktop: [1280, 800], Phone: [390, 844] };
const screensHost = () => host('Screens');
const BUILT = [];
/**
 * The frame of the screen [name] on [Device], empty. A screen built before keeps its frame, and with it its node id and the links to it.
 * The desktop's is a window: bar is the kind of its Window title bar.
 */
function screen(name, Device, bar = 'With state') {
  const s = screensHost(), full = `${name} · ${Device}`, [w, h] = SIZE[Device];
  let f = s.children.find((n) => n.name === full);
  if (f) f.children.forEach((k) => k.remove()); else { f = figma.createFrame(); s.appendChild(f); }
  f.name = full; f.setPluginData('script', SCREEN_SCRIPT); f.fills = paint(LEVEL.background.fill); f.clipsContent = true;
  f.layoutMode = 'VERTICAL'; f.itemSpacing = 0; f.counterAxisAlignItems = 'MIN'; f.primaryAxisAlignItems = 'MIN';
  f.resize(w, h); f.primaryAxisSizingMode = 'FIXED'; f.counterAxisSizingMode = 'FIXED';
  if (Device === 'Desktop') add(f, inst('Window title bar', { Kind: bar }), { fillW: true });
  BUILT.push(f);
  return f;
}
/** What fills a screen under the title bar: a row of panels, or with dir 'V' a column. o as for box(). */
const stretch = (parent, name, o = {}) => add(parent, box(name, { dir: 'H', align: 'MIN', ...o }), { fillW: true, fillH: true });
/** Ends a screen script: places the screens of every script in columns, the desktop's above the phone's, and names the ones built. */
async function done() {
  await flush();
  const s = screensHost(), GAP = 120;
  let x = GAP, bottom = 0;
  for (const script of SCREENS) {
    const mine = s.children.filter((n) => n.getPluginData('script') === script);
    const phone = (n) => n.name.endsWith(' · Phone');
    let y = GAP, across = x, right = x;
    for (const f of mine.filter((n) => !phone(n))) { f.x = x; f.y = y; y += f.height + GAP; right = Math.max(right, x + f.width); bottom = Math.max(bottom, y - GAP); }
    for (const f of mine.filter(phone)) { f.x = across; f.y = y; across += f.width + GAP; right = Math.max(right, across - GAP); bottom = Math.max(bottom, y + f.height); }
    if (mine.length) x = right + GAP;
  }
  s.resizeWithoutConstraints(x, bottom + GAP);
  // Above Foundations, clear of the Components section, which grows to the right and down.
  const f = PAGE.children.find((n) => n.name === 'Foundations');
  s.x = f.x; s.y = f.y - s.height - 400;
  return BUILT.map((n) => n.name);
}

// The chats beside an open conversation in the capture; who is the open one is up to the screen.
const CHATS = [
  { Title: 'Weekend plans', Time: '9:20 AM', Preview: 'Leo Park: Leaving at 6 sharp. Coffee is on me.', Unread: true, avatar: { Kind: 'Group', Plate: '1' } },
  { Title: 'Maya Chen', Time: '8:34 AM', Preview: 'You: Here is the route I mapped out.', avatar: { Kind: 'Person', Plate: '2' }, initials: 'MC', online: true },
  { Title: '#photography', Time: '8:14 AM', Preview: 'Leo Park: ND filter and a sturdy tripod.', avatar: { Kind: 'Channel', Plate: '3' } },
  { Title: 'Leo Park', Time: 'Nov 20, 2026', Preview: 'Thanks for the photos!', avatar: { Kind: 'Person', Plate: '4' }, initials: 'LP', online: true },
];
// The chats of the capture's "Chats / List / Chats", as far as a screen shows them.
const person = (Plate, initials, online) => ({ avatar: { Kind: 'Person', Plate }, initials, online });
const ALL_CHATS = [
  { Title: 'Maya Chen', Time: '9:43 AM', Preview: 'See you by the bridge!', Unread: '2', ...person('2', 'MC', true) },
  { Title: 'Weekend plans', Time: '9:31 AM', Preview: 'Leo Park: Saturday works for everyone.', Unread: '5', avatar: { Kind: 'Group', Plate: '1' } },
  { Title: 'Leo Park', Time: '9:12 AM', Preview: 'You: Got it, thanks for the photos too.', ...person('4', 'LP', true) },
  { Title: 'Priya Nair', Time: '8:05 AM', Preview: 'Sharing the venue shortlist now', Unread: '99+', ...person('3', 'PN', true) },
  { Title: '#photography', Time: 'Nov 20, 2026', Preview: 'Nina Alvarez: A few frames from the coast.', avatar: { Kind: 'Channel', Plate: '3' } },
  { Title: '#city-cycling', Time: '', Preview: 'Group rides every Sunday', avatar: { Kind: 'Channel', Plate: '1' } },
  { Title: 'Jonas Weber', Time: '', Preview: 'Contact is offline', ...person('1', 'JW') },
  { Title: 'Sofia Reyes', Time: '', Preview: 'Waiting for your contact', ...person('2', 'SR') },
];
/** The chat list as a panel of [parent], as tall as it; open: the title of the chat that is open, none: the list is empty, of: the chats in it. */
function chats(parent, Device, { open, none, of = CHATS } = {}) {
  const l = add(parent, list('Chats', Device, (rows) => {
    if (none) add(rows, inst('List notice', { Kind: 'No chats', Device }), { fillW: true });
    else of.forEach((c) => add(rows, chat({ ...c, State: c.Title === open ? 'Selected' : 'Default', Unread: c.Title !== open && c.Unread }, Device), { fillW: true }));
  }), { fillH: true });
  // The rows take the room the list has, so settings stays at its foot.
  l.findOne((n) => n.name === 'rows').layoutSizingVertical = 'FILL';
  return l;
}
/** A conversation as a panel of [parent]: its top bar, the end of its feed and the composer. Kind: of the Top bar; banner: a kind of Banner over the feed. */
function conversation(parent, Device, Kind, items, banner) {
  const c = add(parent, surface('conversation', 'background', { dir: 'V', align: 'MIN' }), { fillW: true, fillH: true });
  add(c, inst('Top bar', { Kind, Device }), { fillW: true });
  if (banner) add(add(c, box('banner', { dir: 'H', pad: [0, feedPad(Device), 2, feedPad(Device)] }), { fillW: true }), inst('Banner', { Kind: banner, Device }), { fillW: true });
  // The feed is read from its end: what does not fit leaves at the top.
  const view = add(c, box('feed', { dir: 'V', justify: 'MAX', clip: true }), { fillW: true, fillH: true });
  add(view, thread('thread', Device, items), { fillW: true });
  add(add(c, box('composer', { dir: 'H', pad: [0, feedPad(Device), Device === 'Phone' ? 2 : 4, feedPad(Device)] }), { fillW: true }), inst('Composer', { State: 'Empty', Device }), { fillW: true });
  return c;
}
/** The screen [name] with the direct chat open: on the desktop beside the chat list, and with details beside the details panel. */
function directChat(name, Device, details = false) {
  const f = screen(name, Device), row = stretch(f, 'panels');
  if (Device === 'Desktop') chats(row, Device, { open: 'Maya Chen' });
  conversation(row, Device, 'Private chat', DM);
  if (details) add(row, inst('Details panel', { Kind: 'Private chat', Device }), { fillH: true });
  return f;
}
