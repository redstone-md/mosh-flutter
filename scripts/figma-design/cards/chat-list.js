// What stands around the rows of the chat list: SessionsListControls (search
// and filters), RailNewButton, RailSettingsButton, CompactRailButton,
// RailDivider and the list's empty states. The lists at the end are assembled
// from these and the chat rows, to judge the list as a whole.
card('Chat list', 'Above the rows: one button to start a conversation, the search and the filters. Below them: settings. The new-chat button is the primary Button, the filters are filter chips, and the collapsed list uses icon buttons, so only the search field, the settings row and the notice of an empty list are new here.');
const SEARCH = { Empty: ['Search chats', 'onSurfaceMuted'], Focus: ['Search chats', 'onSurfaceMuted'], Query: ['cabin', 'onSurface'] };
const fields = await grid('Search field', axis('State', Object.keys(SEARCH)), DEVICES, ({ State, Device }) => {
  const [chars, ink] = SEARCH[State];
  const f = box('Search field', { component: true, dir: 'H', gap: 2, pad: [0, 0, 0, 3], w: ROW[Device], hk: controlHeight(Device), r: 'full', clip: true, fill: 'surfaceContainerHigh' });
  add(f, icon('search', 'onSurfaceVariant'));
  add(f, text(chars, 'bodyMedium', ink, { name: State === 'Query' ? 'query' : 'placeholder', truncate: true }), { fillW: true });
  if (State === 'Query') add(f, action('close', Device)).name = 'clear';
  else if (Device === 'Desktop') {
    const key = add(add(f, box('shortcut', { dir: 'H', pad: [0, 3, 0, 0] })), box('keycap', { dir: 'H', pad: [0, 1], r: 'extraSmall', stroke: 'outlineVariant' }));
    add(key, text('Ctrl K', 'labelSmall', 'onSurfaceMuted'));
  }
  if (State === 'Focus') focusRing(f);
  return f;
});
prop(fields, 'Placeholder', 'TEXT', 'Search chats', 'placeholder');
prop(fields, 'Query', 'TEXT', 'cabin', 'query');
prop(fields, 'Clear', 'BOOLEAN', true, 'clear');
prop(fields, 'Shortcut', 'BOOLEAN', true, 'shortcut');

await grid('Settings row', axis('State', ['Default', 'Hover', 'Pressed', 'Focus', 'Selected']), DEVICES, ({ State, Device }) => {
  const on = State === 'Selected', ink = on ? 'onSecondaryContainer' : 'onSurfaceVariant';
  const r = box('Settings row', { component: true, dir: 'H', gap: 3, pad: [0, 3], w: ROW[Device], hk: controlHeight(Device), r: 'full', clip: true, fill: on ? 'secondaryContainer' : null });
  add(r, icon('settings', ink));
  add(r, text('Settings', 'labelLarge', ink));
  interact(r, State, 'onSurface');
  return r;
});

const NOTICE = { 'No chats': ['No conversations yet', 'Start one, or open an invite link someone sent you'], 'No results': ['Nothing matches “cabin”', 'Search looks through chat names and messages'], 'Could not load': ['The chat list could not be loaded', 'Your chats are safe on this device. Try again.'] };
display(await grid('List notice', axis('Kind', Object.keys(NOTICE)), DEVICES, ({ Kind, Device }) => {
  const [title, detail] = NOTICE[Kind], failed = Kind === 'Could not load';
  const n = box('List notice', { component: true, dir: 'V', gap: 1, pad: [6, 4], w: ROW[Device], align: 'MIN' });
  add(n, text(title, 'titleSmall', failed ? 'error' : 'onSurface', { w: 260 }), { fillW: true });
  add(n, text(detail, 'bodySmall', 'onSurfaceVariant', { w: 260 }), { fillW: true });
  if (failed) add(n, setProps(inst('Button', { Kind: 'Outlined', Device, State: 'Default' }), { Label: 'Try again' }));
  return n;
}));

const CHATS = [
  { Title: 'Weekend plans', Time: '9:20 AM', Preview: 'Leo Park: Leaving at 6 sharp. Coffee is on me.', Unread: true, avatar: { Kind: 'Group', Plate: '1' } },
  { Title: 'Maya Chen', Time: '8:34 AM', Preview: 'You: Here is the route I mapped out.', State: 'Selected', avatar: { Kind: 'Person', Plate: '2' }, initials: 'MC', online: true },
  { Title: '#photography', Time: '8:14 AM', Preview: 'Leo Park: ND filter and a sturdy tripod.', avatar: { Kind: 'Channel', Plate: '3' } },
  { Title: 'Bartholomew Featherstonehaugh-Cholmondeley', Time: 'Nov 20, 2026', Preview: 'https://maps.example.org/routes/coast/2026/november/lighthouse-loop', avatar: { Kind: 'Person', Plate: '4' }, initials: 'BF' },
  { Title: 'Sofia Reyes', Time: '', Preview: '', bare: true, avatar: { Kind: 'Person', Plate: '1' }, initials: 'SR' },
];
const full = (Device) => list('Chats', Device, (rows) => CHATS.forEach((c) => add(rows, chat(c, Device), { fillW: true })));
await examples('Chats, with a long name and a chat without a last message', [full('Desktop'), full('Phone')], 'MIN');
const invited = list('Invitations', 'Desktop', (rows) => {
  add(add(rows, box('label', { dir: 'H', pad: [1, 3] })), text('Invitations', 'labelLarge', 'onSurfaceMuted'));
  for (const [Title, Detail, initials, Plate] of [['Nina Alvarez', '#photography', 'NA', '3'], ['Omar Haddad', 'Group invite', 'OH', '4']]) {
    dressAvatar(add(rows, setProps(inst('Invitation row', { Device: 'Desktop' }), { Title, Detail }), { fillW: true }), { Plate, Size: 'Small' }, { Initials: initials });
  }
  add(rows, inst('Divider', { Orientation: 'Horizontal' }), { fillW: true });
  CHATS.slice(0, 2).forEach((c) => add(rows, chat({ ...c, State: 'Default' }, 'Desktop'), { fillW: true }));
});
const notice = (Kind, query) => list(Kind, 'Desktop', (rows) => add(rows, inst('List notice', { Kind, Device: 'Desktop' }), { fillW: true }), query);
const QUERY = 'ma', matches = (c) => (c.Title + ' ' + c.Preview).toLowerCase().includes(QUERY);
const found = list('Search results', 'Desktop', (rows) => CHATS.filter(matches).forEach((c) => add(rows, chat({ ...c, State: 'Default' }, 'Desktop'), { fillW: true })), QUERY);
// The collapsed list is a column of 48 px buttons, the size the phone uses, beside 64 px rows.
function collapsed(failed) {
  const l = surface(failed ? 'Collapsed, could not load · Desktop' : 'Collapsed · Desktop', 'panel', { dir: 'V', gap: 2, pad: [4, 2] });
  add(l, action('add', 'Phone', { Kind: 'Tonal', ink: 'onPrimary' })).fills = paint('primary');
  add(l, action('search', 'Phone', { Kind: 'Tonal' }));
  if (failed) add(l, action('error', 'Phone', { Kind: 'Tonal', ink: 'error' }));
  else CHATS.slice(0, 4).forEach((c) => {
    const row = add(l, setProps(inst('Compact chat row', { State: c.State ?? 'Default' }), { Unread: !!c.Unread }));
    dressAvatar(row, { ...c.avatar, Size: 'Medium' }, c.initials ? { Initials: c.initials } : {});
  });
  add(l, action('settings', 'Phone', { Kind: 'Tonal' }));
  return l;
}
await examples('Invitations, search results, no results, no chats, could not load', [invited, found, notice('No results', 'cabin'), notice('No chats'), notice('Could not load')], 'MIN');
await examples('Collapsed, and collapsed when the list could not be loaded', [collapsed(false), collapsed(true)], 'MIN');
