// Plugin-side helpers of the screens in screens/: screens.mjs appends this file
// to the prelude of run.mjs. A screen is a frame of the capture's size in the
// "Screens" section of the Redesign page, filled with instances of the
// components and the frames that lay them out, and with the capture's data, so
// it can be put beside its frame on the "current" pages.
const SIZE = { Desktop: [1280, 800], Phone: [390, 844] };
// What is on the page before the script adds to it: a script that throws takes back the rest.
const BEFORE = new Set(PAGE.children.map((n) => n.id));
function screensHost() {
  let s = PAGE.children.find((n) => n.type === 'SECTION' && n.name === 'Screens');
  if (!s) { s = figma.createSection(); s.name = 'Screens'; s.fills = paint('surfaceDim'); PAGE.appendChild(s); BEFORE.add(s.id); }
  return s;
}
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
const fill = (parent, name, o = {}) => add(parent, box(name, { dir: 'H', align: 'MIN', ...o }), { fillW: true, fillH: true });
/** Takes back what a script that threw had added to the page outside the frames of its screens. */
function scrap() { for (const n of PAGE.children) if (!BEFORE.has(n.id)) n.remove(); }
/** Ends a screen script: places the screens of every script in columns, the desktop's above the phone's, and names the ones built. */
async function done() {
  await flush();
  const s = screensHost(), GAP = 120;
  let x = GAP, bottom = 0;
  for (const script of SCREENS) {
    const mine = s.children.filter((n) => n.getPluginData('script') === script);
    let y = GAP, px = x, right = x;
    for (const f of mine.filter((n) => n.width > SIZE.Phone[0])) { f.x = x; f.y = y; y += f.height + GAP; right = Math.max(right, x + f.width); }
    for (const f of mine.filter((n) => n.width <= SIZE.Phone[0])) { f.x = px; f.y = y; px += f.width + GAP; right = Math.max(right, px - GAP); bottom = Math.max(bottom, y + f.height); }
    if (mine.length) x = right + GAP;
  }
  s.resizeWithoutConstraints(x, bottom + GAP);
  // Above Foundations, clear of the Components section, which grows to the right and down.
  const f = PAGE.children.find((n) => n.name === 'Foundations');
  s.x = f.x; s.y = f.y - s.height - 400;
  return BUILT.map((n) => n.name);
}

// The chats of the capture's list; who is the open one is up to the screen.
const CHATS = [
  { Title: 'Weekend plans', Time: '9:20 AM', Preview: 'Leo Park: Leaving at 6 sharp. Coffee is on me.', Unread: true, avatar: { Kind: 'Group', Plate: '1' } },
  { Title: 'Maya Chen', Time: '8:34 AM', Preview: 'You: Here is the route I mapped out.', avatar: { Kind: 'Person', Plate: '2' }, initials: 'MC', online: true },
  { Title: '#photography', Time: '8:14 AM', Preview: 'Leo Park: ND filter and a sturdy tripod.', avatar: { Kind: 'Channel', Plate: '3' } },
  { Title: 'Leo Park', Time: 'Nov 20, 2026', Preview: 'Thanks for the photos!', avatar: { Kind: 'Person', Plate: '4' }, initials: 'LP', online: true },
];
/** The chat list as a panel of [parent], as tall as it; open: the title of the chat that is open, none: the list is empty. */
function chats(parent, Device, { open, none } = {}) {
  const l = add(parent, list('Chats', Device, (rows) => {
    if (none) add(rows, inst('List notice', { Kind: 'No chats', Device }), { fillW: true });
    else CHATS.forEach((c) => add(rows, chat({ ...c, State: c.Title === open ? 'Selected' : 'Default', Unread: c.Unread && c.Title !== open }, Device), { fillW: true }));
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
  const f = screen(name, Device), row = fill(f, 'panels');
  if (Device === 'Desktop') chats(row, Device, { open: 'Maya Chen' });
  conversation(row, Device, 'Private chat', DM);
  if (details) add(row, inst('Details panel', { Kind: 'Private chat', Device }), { fillH: true });
  return f;
}
