// Menus: MoshMenuItem and MenuItemButton in the menus of a chat row, the chat
// header and a message (message_context_menu._MessageMenuPanel), and the phone's
// sheet, which stands in for a menu of choices there.
card('Menu', 'A menu lists what can be done with the thing it was opened on, the commonest first. An action that cannot be undone comes last, in the error colour and under a line of its own. The menu floats on the popup level and closes on a choice or a press beside it. Where the list is a choice between values (a microphone, a language, a network adapter) the desktop keeps the menu and the phone slides a sheet up from the bottom edge.');
function menuItem({ Tone, State, Device }) {
  const ink = Tone === 'Destructive' ? 'error' : 'onSurface', off = State === 'Disabled';
  const m = box('Menu item', { component: true, dir: 'H', gap: 3, pad: [0, 4, 0, 3], w: 216, hk: controlHeight(Device), r: 'small', clip: true });
  const glyph = add(m, icon('edit', Tone === 'Destructive' ? 'error' : 'onSurfaceVariant'));
  glyph.name = 'glyph';
  const label = add(m, text('Rename chat', 'labelLarge', ink, { name: 'label', truncate: true }), { fillW: true });
  if (off) disable(m, [glyph, label]);
  interact(m, State, ink);
  return m;
}
const items = await grid('Menu item', perDevice(axis('Tone', ['Default', 'Destructive'])), STATES5, menuItem);
prop(items, 'Label', 'TEXT', 'Rename chat', 'label');
prop(items, 'Icon glyph', 'INSTANCE_SWAP', ICONS.edit, 'glyph');

// Per menu: [glyph, label] in order; the last entry of a list marked `ends` is the destructive one.
const MENUS = {
  'Chat row': { items: [['edit', 'Rename chat']] },
  'Private chat': { items: [['info', 'Conversation details'], ['attach', 'Files'], ['edit', 'Rename chat'], ['delete', 'Delete chat']], ends: true },
  Group: { items: [['info', 'Conversation details'], ['attach', 'Files'], ['edit', 'Rename chat'], ['leave', 'Leave group']], ends: true },
  Channel: { items: [['info', 'Conversation details'], ['attach', 'Files'], ['leave', 'Leave channel']], ends: true },
  Message: { items: [['copy', 'Copy message'], ['success', 'Select message'], ['select_all', 'Select all'], ['delete', 'Delete…']], ends: true },
  'Shared file': { items: [['download', 'Save as…'], ['copy', 'Copy file name'], ['success', 'Select message'], ['delete', 'Delete…']], ends: true },
};
display(await grid('Menu', axis('Kind', Object.keys(MENUS)), DEVICES, ({ Kind, Device }) => {
  const { items: list, ends } = MENUS[Kind];
  const m = surface('Menu', 'popup', { component: true, dir: 'V', pad: 2, gap: 1, w: 232, r: 'large', align: 'MIN' });
  list.forEach(([glyph, Label], i) => {
    const last = ends && i === list.length - 1;
    if (last) add(m, inst('Divider', { Orientation: 'Horizontal' }), { fillW: true });
    add(m, setProps(inst('Menu item', { Tone: last ? 'Destructive' : 'Default', State: 'Default', Device }), { Label, 'Icon glyph': ICONS[glyph] ?? fail('Icon/' + glyph) }), { fillW: true });
  });
  return m;
}));

// A sheet's title and its choices, the second one chosen.
const SHEETS = {
  Microphone: ['System default', 'USB Microphone', 'Built-in Microphone'],
  Language: ['System language', 'English', 'Русский'],
  'Network adapter': ['Automatic', 'Ethernet, 192.168.1.24', 'Wi-Fi, 192.168.1.31'],
};
display(await grid('Sheet', ONE, axis('Kind', Object.keys(SHEETS)), ({ Kind }) => {
  const s = surface('Sheet', 'modal', { component: true, dir: 'V', pad: [3, 3, 6, 3], gap: 2, w: SCREEN.Phone, stroke: null });
  ['topLeftRadius', 'topRightRadius'].forEach((f) => bind(s, f, 'radius/extraLarge'));
  add(s, rect('handle', { fill: 'outline', wk: 8, hk: 1, r: 'full' }));
  const head = add(s, box('title', { dir: 'H', pad: [0, 0, 0, 3] }), { fillW: true });
  add(head, text(Kind, 'titleMedium', 'onSurface', { name: 'sheet title' }), { fillW: true });
  add(head, action('close', 'Phone'));
  SHEETS[Kind].forEach((Label, i) => add(s, setProps(inst('Select option', { State: i === 1 ? 'Selected' : 'Default', Device: 'Phone' }), { Label }), { fillW: true }));
  return s;
}));

const adapters = surface('Adapter menu', 'popup', { dir: 'V', pad: 2, gap: 1, w: 280, r: 'large' });
SHEETS['Network adapter'].forEach((Label, i) => add(adapters, setProps(inst('Select option', { State: i === 1 ? 'Selected' : 'Default', Device: 'Desktop' }), { Label }), { fillW: true }));
await examples('The adapter menu on the desktop is the Select menu', [adapters], 'MIN');
