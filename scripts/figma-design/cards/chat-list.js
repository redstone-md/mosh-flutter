// What stands around the rows of the chat list: SessionsListControls (search
// and filters), RailNewButton, RailSettingsButton, CompactRailButton,
// RailDivider and the list's empty states. The lists at the end are assembled
// from these and the chat rows, to judge the list as a whole.
card('Chat list', 'Above the rows: one button to start a conversation, the search and the filters. Below them: settings. The new-chat button is the primary Button, the filters are filter chips, and the collapsed list uses icon buttons, so only the search field, the settings row and the notice of an empty list are new here.');
const ROW = { Desktop: 324, Phone: 358 };
const SEARCH = { Empty: ['Search chats', 'onSurfaceMuted'], Focus: ['Search chats', 'onSurfaceMuted'], Query: ['cabin', 'onSurface'] };
const fields = await grid('Search field', axis('State', Object.keys(SEARCH)), axis('Device', ['Desktop', 'Phone']), ({ State, Device }) => {
  const [chars, ink] = SEARCH[State];
  const f = box('Search field', { component: true, dir: 'H', gap: 2, pad: [0, 1, 0, 3], w: ROW[Device], hk: controlHeight(Device), r: 'full', clip: true, fill: 'surfaceContainerHigh' });
  add(f, icon('search', 'onSurfaceVariant'));
  add(f, text(chars, 'bodyMedium', ink, { name: 'text ' + State, truncate: true }), { fillW: true });
  if (State === 'Query') add(f, action('close', 'Desktop')).name = 'clear';
  else if (Device === 'Desktop') {
    const key = add(add(f, box('shortcut', { dir: 'H', pad: [0, 2, 0, 0] })), box('keycap', { dir: 'H', pad: [0, 1], r: 'extraSmall', stroke: 'outlineVariant' }));
    add(key, text('Ctrl K', 'labelSmall', 'onSurfaceMuted'));
  }
  if (State === 'Focus') focusRing(f);
  return f;
});
prop(fields, 'Placeholder', 'TEXT', 'Search chats', 'text Empty');
prop(fields, 'Query', 'TEXT', 'cabin', 'text Query');
prop(fields, 'Shortcut', 'BOOLEAN', true, 'shortcut');

const settings = await grid('Settings row', axis('State', ['Default', 'Hover', 'Pressed', 'Focus', 'Selected']), axis('Device', ['Desktop', 'Phone']), ({ State, Device }) => {
  const on = State === 'Selected', ink = on ? 'onSecondaryContainer' : 'onSurfaceVariant';
  const r = box('Settings row', { component: true, dir: 'H', gap: 3, pad: [0, 3], w: ROW[Device], hk: controlHeight(Device), r: 'full', clip: true, fill: on ? 'secondaryContainer' : null });
  add(r, icon('settings', ink));
  add(r, text('Settings', 'labelLarge', ink));
  interact(r, State, 'onSurface');
  return r;
});

const NOTICE = { 'No chats': ['No conversations yet', 'Start one, or open an invite link someone sent you.'], 'No results': ['Nothing matches “cabin”', 'Search looks through chat names and messages.'], 'Could not load': ['The chat list could not be loaded', 'Your chats are safe on this device. Try again.'] };
await grid('List notice', ONE, axis('Kind', Object.keys(NOTICE)), ({ Kind }) => {
  const [title, detail] = NOTICE[Kind], failed = Kind === 'Could not load';
  const n = box('List notice', { component: true, dir: 'V', gap: 1, pad: [6, 4], w: ROW.Desktop, align: 'MIN' });
  add(n, text(title, 'titleSmall', failed ? 'error' : 'onSurface', { w: 260 }), { fillW: true });
  add(n, text(detail, 'bodySmall', 'onSurfaceVariant', { w: 260 }), { fillW: true });
  if (failed) add(n, setProps(inst('Button', { Kind: 'Outlined', Device: 'Desktop', State: 'Default' }), { Label: 'Try again' }));
  return n;
});

const CHATS = [
  { Title: 'Weekend plans', Time: '9:20 AM', Preview: 'Leo Park: Leaving at 6 sharp. Coffee is on me.', Unread: true, avatar: { Kind: 'Group', Plate: '1' } },
  { Title: 'Maya Chen', Time: '8:34 AM', Preview: 'You: Here is the route I mapped out.', State: 'Selected', avatar: { Kind: 'Person', Plate: '2' }, initials: 'MC', online: true },
  { Title: '#photography', Time: '8:14 AM', Preview: 'Leo Park: ND filter and a sturdy tripod.', avatar: { Kind: 'Channel', Plate: '3' } },
  { Title: 'Bartholomew Featherstonehaugh-Cholmondeley', Time: 'Nov 20, 2026', Preview: 'https://maps.example.org/routes/coast/2026/november/lighthouse-loop', avatar: { Kind: 'Person', Plate: '4' }, initials: 'BF' },
  { Title: 'Sofia Reyes', Time: '', Preview: '', bare: true, avatar: { Kind: 'Person', Plate: '1' }, initials: 'SR' },
];
/** Sets an exposed avatar to another kind and plate. */
function dressAvatar(row, size, c) {
  const a = row.findOne((n) => n.name === 'avatar');
  a.swapComponent(variant('Avatar', { ...c.avatar, Size: size }));
  if (c.initials) setProps(a, { Initials: c.initials });
  if (c.online) setProps(a, { Presence: true });
}
function chat(c, Device) {
  const row = setProps(inst('Chat row', { State: c.State ?? 'Default', Device }), { Title: c.Title, Time: c.Time, Preview: c.Preview, Unread: !!c.Unread, 'Show preview': !c.bare });
  dressAvatar(row, 'Medium', c);
  return row;
}
/** A chat list on [Device]; body(list) adds what sits between the filters and the settings row. */
function list(name, Device, body) {
  const l = box(`${name} · ${Device}`, { dir: 'V', gap: 2, pad: [4, 2], w: ROW[Device] + 16, fill: 'surfaceContainerLow', align: 'MIN' });
  add(l, setProps(inst('Button', { Kind: 'Primary', Device, State: 'Default' }), { Label: 'Start a conversation', Icon: true }), { fillW: true });
  add(l, inst('Search field', { State: 'Empty', Device }), { fillW: true });
  const chips = add(l, box('filters', { dir: 'H', gap: 1 }));
  ['All', 'Personal', 'Groups', 'Channels'].forEach((label, i) => add(chips, setProps(inst('Filter chip', { Selected: i ? 'No' : 'Yes', State: 'Default', Device: 'Desktop' }), { Label: label })));
  body(add(l, box('rows', { dir: 'V', gap: 1, align: 'MIN' }), { fillW: true }));
  add(l, inst('Settings row', { State: 'Default', Device }), { fillW: true });
  return l;
}
const full = (Device) => list('Chats', Device, (rows) => CHATS.forEach((c) => add(rows, chat(c, Device), { fillW: true })));
(await examples('Chats, with a long name and a chat without a last message', [full('Desktop'), full('Phone')])).counterAxisAlignItems = 'MIN';
const invited = list('Invitations', 'Desktop', (rows) => {
  add(add(rows, box('label', { dir: 'H', pad: [1, 3] })), text('Invitations', 'labelLarge', 'onSurfaceMuted'));
  for (const [Title, Detail, initials, Plate] of [['Nina Alvarez', '#photography', 'NA', '3'], ['Omar Haddad', 'Group invite', 'OH', '4']]) {
    dressAvatar(add(rows, setProps(inst('Invitation row', { Device: 'Desktop' }), { Title, Detail }), { fillW: true }), 'Small', { avatar: { Kind: 'Person', Plate }, initials });
  }
  add(rows, inst('Divider', { Orientation: 'Horizontal' }), { fillW: true });
  CHATS.slice(0, 2).forEach((c) => add(rows, chat({ ...c, State: 'Default' }, 'Desktop'), { fillW: true }));
});
const notice = (Kind) => list(Kind, 'Desktop', (rows) => add(rows, inst('List notice', { Kind }), { fillW: true }));
const collapsed = box('Collapsed · Desktop', { dir: 'V', gap: 2, pad: [4, 2], fill: 'surfaceContainerLow' });
const plus = add(collapsed, action('add', 'Phone', { Kind: 'Tonal', ink: 'onPrimary' })); plus.fills = paint('primary');
add(collapsed, action('search', 'Phone', { Kind: 'Tonal' }));
CHATS.slice(0, 4).forEach((c) => {
  const row = add(collapsed, setProps(inst('Compact chat row', { State: c.State ?? 'Default' }), { Unread: !!c.Unread }));
  dressAvatar(row, 'Medium', c);
});
add(collapsed, action('settings', 'Phone', { Kind: 'Tonal' }));
(await examples('Invitations, no results, no chats, could not load, collapsed', [invited, notice('No results'), notice('No chats'), notice('Could not load'), collapsed])).counterAxisAlignItems = 'MIN';
