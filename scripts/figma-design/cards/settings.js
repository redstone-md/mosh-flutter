// Settings: SettingsSurface with SettingsCardHeader, SettingsIcon and its
// ListTile rows and ExpansionTile; SettingsNav with its section rows; the
// start menu's StartRow and section label; LinkedDeviceList with its device,
// id and revocation rows.
card('Settings', 'A settings screen is a column of cards, one subject to a card. The card names its subject beside a small plate with its icon, and puts the one control that matters most at the right of that header. What explains the control is folded under a line that opens. The navigation rows lead to the sections, and on the phone they are the whole first screen. A device row tells this device from the others, and a device being removed says how far the removal has got.');
const CARD_W = { Desktop: 560, Phone: 358 };
const disclosures = await grid('Disclosure', axis('State', ['Closed', 'Hover', 'Focus', 'Open']), DEVICES, ({ State, Device }) => {
  const d = box('Disclosure', { component: true, dir: 'H', gap: 2, pad: [0, 2, 0, 3], w: 320, hk: controlHeight(Device), r: 'small', clip: true });
  add(d, text('What is sent', 'labelLarge', 'onSurfaceVariant', { name: 'label', truncate: true }), { fillW: true });
  const caret = add(d, icon('expand_more', State === 'Open' ? 'primary' : 'onSurfaceVariant'));
  if (State === 'Open') caret.rotation = 180;
  interact(d, State, 'onSurface');
  return d;
});
prop(disclosures, 'Label', 'TEXT', 'What is sent', 'label');

const facts = display(await grid('Fact row', ONE, DEVICES, ({ Device }) => {
  const r = box('Fact row', { component: true, dir: 'H', gap: 4, w: 320, minHk: controlHeight(Device) - 2 });
  add(r, text('Version', 'bodyMedium', 'onSurfaceVariant', { name: 'label' }));
  const v = add(r, text('0.21.4, build 214', 'bodyMedium', 'onSurface', { name: 'value', truncate: true }), { fillW: true });
  v.textAlignHorizontal = 'RIGHT';
  return r;
}));
prop(facts, 'Label', 'TEXT', 'Version', 'label');
prop(facts, 'Value', 'TEXT', '0.21.4, build 214', 'value');

const CRASH = ['Send crash reports', 'Help fix errors in Mosh. Off by default.'];
const SENT = 'Reports go to Sentry and hold stack traces, error types, the Mosh version and the system. They leave out messages, contacts, keys, invites and IP addresses, and replace identifiers with hashes.';
// Per kind: what the card holds under its header.
const CARDS = {
  Facts: (c, Device) => {
    header(c, 'shield', 'Mosh', 'Private messaging without a server in the middle');
    for (const [Label, Value] of [['Version', '0.21.4, build 214'], ['Encryption', 'OpenMLS'], ['Network', 'Moss 0.9.3']]) add(c, setProps(inst('Fact row', { Device }), { Label, Value }), { fillW: true });
    add(c, inst('Update notice', { State: 'Available', Device }), { fillW: true });
  },
  Control: (c, Device) => {
    header(c, 'mic', 'Microphone', 'Used for calls and voice messages');
    add(c, setProps(inst('Select', { State: 'Closed', Device }), { Label: 'Input device' }), { fillW: true });
  },
  'Switch': (c, Device) => {
    header(c, 'bug', ...CRASH, inst('Switch', { Value: 'Off', State: 'Default', Device }));
    add(c, inst('Divider', { Orientation: 'Horizontal' }), { fillW: true });
    add(c, inst('Disclosure', { State: 'Closed', Device }), { fillW: true });
  },
  'Switch and details': (c, Device) => {
    header(c, 'bug', ...CRASH, inst('Switch', { Value: 'On', State: 'Default', Device }));
    add(c, inst('Divider', { Orientation: 'Horizontal' }), { fillW: true });
    add(c, inst('Disclosure', { State: 'Open', Device }), { fillW: true });
    para(add(c, box('details', { dir: 'V', pad: [0, 3] }), { fillW: true }), SENT, 'bodySmall', 'onSurfaceVariant', 'details');
  },
  Loading: (c) => {
    header(c, 'devices', 'Your devices', 'Looking for the devices linked to you', inst('Circular progress', { Size: 'Small' }));
  },
  'Could not load': (c, Device) => {
    header(c, 'devices', 'Your devices', null, button(Device, 'Try again', { Kind: 'Outlined' }));
    add(c, setProps(inst('Inline error'), { Message: 'The list of devices could not be loaded' }), { fillW: true });
  },
};
display(await grid('Settings card', axis('Kind', Object.keys(CARDS)), DEVICES, ({ Kind, Device }) => {
  const c = cardSurface('Settings card', { component: true, dir: 'V', gap: 3, pad: Device === 'Phone' ? 4 : 5, w: CARD_W[Device], align: 'MIN' });
  CARDS[Kind](c, Device);
  return c;
}));

const SECTIONS = [['mic', 'Sound and video'], ['person', 'Profile'], ['devices', 'Devices'], ['link', 'Connection'], ['lock', 'Privacy'], ['info', 'About']];
const navs = await grid('Navigation row', axis('State', ['Default', 'Hover', 'Pressed', 'Focus', 'Selected']), DEVICES, ({ State, Device }) => {
  const on = State === 'Selected', ink = on ? 'onSecondaryContainer' : 'onSurfaceVariant', phone = Device === 'Phone';
  const r = box('Navigation row', { component: true, dir: 'H', gap: 3, pad: [0, 3, 0, 4], w: phone ? 358 : 232, hk: phone ? 12 : 10, r: 'full', clip: true, fill: on ? 'secondaryContainer' : null });
  add(r, icon('devices', ink)).name = 'glyph';
  add(r, text('Devices', 'labelLarge', on ? 'onSecondaryContainer' : 'onSurface', { name: 'label', truncate: true }), { fillW: true });
  // The phone's row opens a screen of its own, and says so.
  if (phone) add(r, icon('chevron_right', 'onSurfaceMuted', 4));
  interact(r, State, 'onSurface');
  return r;
});
prop(navs, 'Label', 'TEXT', 'Devices', 'label');
prop(navs, 'Icon glyph', 'INSTANCE_SWAP', ICONS.devices, 'glyph');

// The start menu: what a new conversation can be. Per row: glyph, its tint, title, line.
const STARTS = [['chat', 'primary', 'Start a private chat', 'A secure one-to-one conversation'], ['group', 'secondary', 'Create a group', 'A closed group for your team or friends'], ['link', 'onSurfaceVariant', 'Join with a link', 'Use an invite a contact sent you'], ['tag', 'tertiary', 'Join a public channel', 'An open room anyone can read, not encrypted']];
const starts = await grid('Start row', STATES5.slice(0, 4), DEVICES, ({ State, Device }) => {
  const r = box('Start row', { component: true, dir: 'H', gap: 4, pad: [3, 4], w: CARD_W[Device] - 120 * (Device === 'Desktop'), minHk: 16, r: 'large', clip: true });
  add(r, icon('chat', 'primary', 6)).name = 'glyph';
  const col = add(r, box('text', { dir: 'V', align: 'MIN' }), { fillW: true });
  add(col, text(STARTS[0][2], 'titleSmall', 'onSurface', { name: 'title', truncate: true }), { fillW: true });
  add(col, text(STARTS[0][3], 'bodySmall', 'onSurfaceVariant', { name: 'line', truncate: true }), { fillW: true });
  add(r, icon('chevron_right', 'onSurfaceMuted', 4));
  interact(r, State, 'onSurface');
  return r;
});
prop(starts, 'Title', 'TEXT', STARTS[0][2], 'title');
prop(starts, 'Line', 'TEXT', STARTS[0][3], 'line');
prop(starts, 'Icon glyph', 'INSTANCE_SWAP', ICONS.chat, 'glyph');

// Per kind: name, id, the note under them and its ink, and whether the device can be removed.
const DEVICES_OF = {
  'This device': ['alex-workstation', '7f3a9c1e…9c1e', 'This device', 'primary', false],
  Linked: ['Studio MacBook Air', '9e62a5f0…a5f0', null, null, true],
  'Removal pending': ['Pixel 8', '51c0d9aa…d9aa', 'Being removed. The others apply it when they come online.', 'onSurfaceVariant', false],
  'Removal applied': ['Old ThinkPad', '0b77e4c2…e4c2', 'Removed. Messages it already received stay on it.', 'onSurfaceVariant', false],
};
display(await grid('Device row', axis('Kind', Object.keys(DEVICES_OF)), DEVICES, ({ Kind, Device }) => {
  const [name, id, note, ink, removable] = DEVICES_OF[Kind], gone = Kind.startsWith('Removal');
  const r = box('Device row', { component: true, dir: 'H', gap: 3, pad: [2, removable ? 1 : 4, 2, 4], w: CARD_W[Device] - 40, minHk: 16, r: 'small', fill: 'surfaceContainer' });
  const glyph = add(r, icon(gone ? 'link_off' : 'devices', 'onSurfaceVariant'));
  const col = add(r, box('text', { dir: 'V', align: 'MIN' }), { fillW: true });
  const title = add(col, text(name, 'titleSmall', 'onSurface', { name: 'name', truncate: true }), { fillW: true });
  add(col, text(id, 'bodySmall', 'onSurfaceMuted', { name: 'id', truncate: true }), { fillW: true });
  if (note) para(col, note, 'bodySmall', ink, 'note');
  if (removable) add(r, action('link_off', Device)).name = 'remove';
  if (Kind === 'Removal applied') disable(r, [glyph, title]);
  return r;
}));

/** The sections of settings as the desktop's side list and as the phone's first screen. */
function sections(Device) {
  const l = surface(`Sections · ${Device}`, Device === 'Phone' ? 'background' : 'panel', { dir: 'V', gap: 1, pad: [4, Device === 'Phone' ? 4 : 2], align: 'MIN' });
  add(add(l, box('heading', { dir: 'H', pad: [0, 4, 2, 4] })), text('Settings', 'titleLarge', 'onSurface'));
  SECTIONS.forEach(([glyph, Label], i) => add(l, setProps(inst('Navigation row', { State: i === 2 && Device === 'Desktop' ? 'Selected' : 'Default', Device }), { Label, 'Icon glyph': ICONS[glyph] })));
  return l;
}
function startMenu() {
  const m = surface('Start menu', 'background', { dir: 'V', gap: 2, pad: 4, align: 'MIN' });
  const label = (glyph, chars) => { const l = add(m, box('label', { dir: 'H', gap: 2, pad: [2, 4, 0, 4] })); add(l, icon(glyph, 'onSurfaceMuted', 4)); add(l, text(chars, 'labelLarge', 'onSurfaceMuted')); };
  const group = (rows) => { const g = add(m, cardSurface('group', { dir: 'V', r: 'large' })); rows.forEach(([glyph, tint, Title, Line]) => { const r = add(g, setProps(inst('Start row', { State: 'Default', Device: 'Desktop' }), { Title, Line, 'Icon glyph': ICONS[glyph] })); if (tint !== 'primary') r.findOne((n) => n.name === 'glyph').children[0].fills = paint(tint); }); };
  label('lock', 'End-to-end encrypted'); group(STARTS.slice(0, 3));
  label('language', 'Open to everyone'); group(STARTS.slice(3));
  return m;
}
function deviceList() {
  const c = cardSurface('Your devices', { dir: 'V', gap: 2, pad: 5, w: CARD_W.Desktop, align: 'MIN' });
  add(add(c, box('heading', { dir: 'H', pad: [0, 0, 1, 0] })), text('Your devices', 'titleMedium', 'onSurface'));
  Object.keys(DEVICES_OF).forEach((Kind) => add(c, inst('Device row', { Kind, Device: 'Desktop' }), { fillW: true }));
  return c;
}
await examples('The sections on the desktop and on the phone, and the start menu', [sections('Desktop'), sections('Phone'), startMenu()], 'MIN');
await examples('The devices of one user', [deviceList()], 'MIN');
