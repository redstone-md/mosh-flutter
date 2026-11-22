// Rows of the chat list: RailItem with its text (rail_item._RailText), the
// invitation row, CompactRailItem of the collapsed list, and ChatRowMenu, the
// menu a row opens.
card('Chat row', 'A chat is its avatar, its name, the last message and when it came. The open chat is the one filled row in the list, the same for a person, a group and a channel: the avatar already tells them apart. A long name and a long message are cut at the end, never wrapped. An invitation offers its two answers in the row. With the list collapsed only the avatar is left.');
function chatRow({ State, Device }) {
  const on = State === 'Selected';
  const r = box('Chat row', { component: true, dir: 'H', gap: 3, pad: [2, 3], w: ROW[Device], minHk: 16, r: 'large', clip: true, fill: on ? 'secondaryContainer' : null });
  avatarSlot(r, { Plate: '2', Size: 'Medium' });
  const col = add(r, box('text', { dir: 'V', align: 'MIN' }), { fillW: true });
  const top = add(col, box('top', { dir: 'H', gap: 2 }), { fillW: true });
  add(top, text('Maya Chen', 'titleMedium', 'onSurface', { name: 'title', truncate: true }), { fillW: true });
  add(top, text('8:34 AM', 'labelMedium', 'onSurfaceMuted', { name: 'time' }));
  const bottom = add(col, box('bottom', { dir: 'H', gap: 2 }), { fillW: true });
  add(bottom, text('You: Here is the route I mapped out.', 'bodyMedium', on ? 'onSecondaryContainer' : 'onSurfaceVariant', { name: 'preview', truncate: true }), { fillW: true });
  add(bottom, inst('Unread badge')).name = 'unread';
  // A row whose menu is open stays pressed under it.
  interact(r, State === 'Menu open' ? 'Pressed' : State, 'onSurface');
  return r;
}
const rows = await grid('Chat row', axis('State', ['Default', 'Hover', 'Pressed', 'Focus', 'Selected', 'Menu open']), DEVICES, chatRow);
prop(rows, 'Title', 'TEXT', 'Maya Chen', 'title');
prop(rows, 'Time', 'TEXT', '8:34 AM', 'time');
prop(rows, 'Preview', 'TEXT', 'You: Here is the route I mapped out.', 'preview');
prop(rows, 'Show preview', 'BOOLEAN', true, 'bottom');
prop(rows, 'Unread', 'BOOLEAN', false, 'unread');

const invitations = await grid('Invitation row', ONE, DEVICES, ({ Device }) => {
  const r = box('Invitation row', { component: true, dir: 'H', gap: 3, pad: [1, 3], w: ROW[Device], minHk: 12 });
  avatarSlot(r, { Plate: '1', Size: 'Small' });
  const col = add(r, box('text', { dir: 'V', align: 'MIN' }), { fillW: true });
  add(col, text('Nina Alvarez', 'titleSmall', 'onSurface', { name: 'title', truncate: true }), { fillW: true });
  add(col, text('#photography', 'bodySmall', 'onSurfaceVariant', { name: 'detail', truncate: true }), { fillW: true });
  const actions = add(r, box('actions', { dir: 'H' }));
  add(actions, action('chat', Device, { ink: 'primary' })).name = 'accept';
  add(actions, action('close', Device)).name = 'decline';
  return r;
});
prop(invitations, 'Title', 'TEXT', 'Nina Alvarez', 'title');
prop(invitations, 'Detail', 'TEXT', '#photography', 'detail');

const compact = await grid('Compact chat row', ONE, axis('State', ['Default', 'Hover', 'Focus', 'Selected']), ({ State }) => {
  const r = box('Compact chat row', { component: true, dir: 'H', wk: 16, hk: 16, r: 'large', clip: true, justify: 'CENTER', fill: State === 'Selected' ? 'secondaryContainer' : null });
  avatarSlot(r, { Plate: '2', Size: 'Medium' });
  const unread = add(r, inst('Unread badge'), { abs: [0, 4] });
  unread.name = 'unread'; unread.x = r.width - unread.width - 4; unread.constraints = { horizontal: 'MAX', vertical: 'MIN' };
  interact(r, State, 'onSurface');
  return r;
});
prop(compact, 'Unread', 'BOOLEAN', false, 'unread');

const menus = await grid('Chat row menu', ONE, DEVICES, ({ Device }) => {
  const m = box('Chat row menu', { component: true, dir: 'V', pad: [1, 0], minWk: 16, minHk: 12, r: 'medium', clip: true, fill: 'surfaceContainerHigh', effect: 'elevation2', align: 'MIN' });
  const item = add(m, box('item', { dir: 'H', gap: 3, pad: [0, 4], hk: controlHeight(Device) }));
  add(item, icon('edit', 'onSurfaceVariant'));
  add(item, text('Rename chat', 'labelLarge', 'onSurface', { name: 'action' }));
  return m;
});
prop(menus, 'Action', 'TEXT', 'Rename chat', 'action');

const KINDS = [['Maya Chen', { Plate: '2' }, { Initials: 'MC' }, 'primary'], ['Weekend plans', { Kind: 'Group', Plate: '1' }, {}, 'secondary'], ['#photography', { Kind: 'Channel', Plate: '3' }, {}, 'tertiary']];
/** The three kinds of chat, selected: in the one tone of the component, or each in the tone of its kind, as the app does today. */
function selected(perKind) {
  const col = box(perKind ? 'A tone per kind' : 'One tone', { dir: 'V', gap: 1 });
  for (const [Title, avatar, values, tone] of KINDS) {
    const row = setProps(inst('Chat row', { State: perKind ? 'Default' : 'Selected', Device: 'Desktop' }), { Title });
    dressAvatar(row, { ...avatar, Size: 'Medium' }, values);
    if (!perKind) { add(col, row); continue; }
    const plate = add(col, box('selected', { dir: 'H', r: 'large', clip: true }));
    add(plate, row);
    tint(plate, tone, 'disabledContainer');
  }
  return col;
}
await examples('Selected: one tone, or a tone per kind', [selected(false), selected(true)]);
const open = box('Row with its menu', { dir: 'H', gap: 2, align: 'MIN' });
add(open, inst('Chat row', { State: 'Menu open', Device: 'Desktop' }));
add(open, inst('Chat row menu', { Device: 'Desktop' }));
await examples('A row with its menu open', [open]);
