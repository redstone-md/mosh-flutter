// The side panel of a conversation (ConversationDetailsPanel with its
// sections) and the connection status that opens from it (PeerStatusDrawer,
// SummaryCard, DiagnosticsGroup, DiagnosticsRow as the Value row, Metric, the event log,
// DiagnosticsEmptyState and RuntimeError).
card('Details and diagnostics', 'The details panel is a panel beside the conversation on the desktop and a screen of its own on the phone: who is here, what was shared, how the conversation is encrypted and how it is connected. Connection status is for looking closely. It opens with a summary a person can read, graded by one word, and keeps the raw values under it in plain rows, label at the left and value at the right, grouped by what they describe.');
const PANEL = { Desktop: 360, Phone: 390 };
/** The head of a panel: its title and its buttons at the right. */
function panelHead(parent, title, Device, glyphs) {
  const h = add(parent, box('head', { dir: 'H', pad: [2, 2, 2, 5], minHk: 16 }), { fillW: true });
  add(h, text(title, 'titleMedium', 'onSurface', { truncate: true }), { fillW: true });
  for (const g of glyphs) add(h, action(g, Device)).name = g;
  return h;
}
function section(parent, title) {
  const s = add(parent, box(title, { dir: 'V', gap: 2, align: 'MIN' }), { fillW: true });
  add(s, text(title, 'titleSmall', 'onSurface'));
  return s;
}
const PEOPLE = [['Alex (you)', 'A', '1', false], ['Leo Park', 'LP', '4', false], ['Maya Chen', 'MC', '2', true], ['Priya Nair', 'PN', '3', false]];
// Per kind: avatar, name, the line under it, how many of PEOPLE take part, shared files, and whether the connection is open.
const PANELS = {
  'Private chat': [{ Kind: 'Person', Plate: '2' }, 'Maya Chen', 'Connected', [0, 2], false, false],
  Group: [{ Kind: 'Group', Plate: '1' }, 'Weekend plans', '4 members', [0, 1, 2, 3], false, false],
  'Shared files': [{ Kind: 'Person', Plate: '2' }, 'Maya Chen', 'Connected', [0, 2], true, false],
  'Connection open': [{ Kind: 'Person', Plate: '2' }, 'Maya Chen', 'Connected', [0, 2], false, true],
  Channel: [{ Kind: 'Channel', Plate: '3' }, '#photography', 'Public channel, not encrypted', [0, 1, 2], false, false],
  Loading: null,
};
const CONNECTION = [['Status', 'Connected'], ['Path', 'Direct'], ['Round trip', '42 ms'], ['Encryption', 'OpenMLS, epoch 12']];
/** A reading: the Value row of the Settings card. */
const row = (parent, Device, [Label, Value]) => add(parent, setProps(inst('Value row', { Device }), { Label, Value }), { fillW: true });

const panels = display(await grid('Details panel', axis('Kind', Object.keys(PANELS)), DEVICES, ({ Kind, Device }) => {
  const p = surface('Details panel', 'panel', { component: true, dir: 'V', w: PANEL[Device], align: 'MIN' });
  panelHead(p, 'Conversation details', Device, ['close']);
  if (!PANELS[Kind]) {
    add(add(p, box('loading', { dir: 'H', pad: [12, 0], justify: 'CENTER' }), { fillW: true }), inst('Circular progress', { Size: 'Medium' }));
    return p;
  }
  const [avatar, name, line, people, files, open] = PANELS[Kind];
  const body = add(p, box('body', { dir: 'V', gap: 6, pad: [2, 5, 6, 5], align: 'MIN' }), { fillW: true });
  const who = add(body, box('identity', { dir: 'V', gap: 1 }), { fillW: true });
  add(who, setProps(inst('Avatar', { ...avatar, Size: 'Large' }), avatar.Kind === 'Person' ? { Initials: 'MC', Presence: true } : {}));
  add(add(who, box('name', { dir: 'H', pad: [2, 0, 0, 0] })), text(name, 'headlineSmall', 'onSurface', { name: 'name' }));
  add(who, text(line, 'bodySmall', 'onSurfaceVariant', { name: 'line' }));
  const members = section(body, 'Participants');
  for (const i of people) {
    const [Name, Initials, Plate, Admin] = PEOPLE[i];
    dressAvatar(add(members, setProps(inst('Member row', { Device }), { Name, 'Show peer': false, Admin: Admin && avatar.Kind === 'Group' }), { fillW: true }), { Plate, Size: 'Compact' }, { Initials });
  }
  const shared = section(body, 'Shared files');
  if (files) add(shared, inst('File card', { Tone: 'Surface', State: 'Ready', Device }), { fillW: true });
  else add(shared, text('No shared files yet', 'bodyMedium', 'onSurfaceMuted'));
  // The one place a conversation shows its encryption: the row opens the fingerprint to compare.
  // A public channel is not encrypted and has no such row.
  if (avatar.Kind !== 'Channel') add(body, setProps(inst('Start row', { State: 'Default', Device }), { Title: 'End-to-end encrypted', Line: 'Compare the fingerprint to verify', 'Icon glyph': glyphOf('lock') }), { fillW: true }).name = 'encryption';
  const link = add(body, box('connection', { dir: 'V', align: 'MIN' }), { fillW: true });
  add(link, setProps(inst('Disclosure', { State: open ? 'Open' : 'Closed', Device }), { Label: 'Connection details' }), { fillW: true });
  if (open) {
    const list = add(link, box('values', { dir: 'V', pad: [0, 3], align: 'MIN' }), { fillW: true });
    CONNECTION.forEach((r) => row(list, Device, r));
    add(list, labelButton(Device, 'Open connection status', { Kind: 'Text' }));
  }
  return p;
}));
// Off for a conversation whose fingerprint is not known yet.
prop(panels, 'Encryption', 'BOOLEAN', true, 'encryption');

/** A small label over a value, and a note under it when [note] is given. */
function cell(label, value, note) {
  const c = box('cell', { dir: 'V', align: 'MIN' });
  add(c, text(label, 'labelSmall', 'onSurfaceMuted'));
  add(c, text(value, 'titleSmall', 'onSurface'));
  if (note) add(c, text(note, 'bodySmall', 'onSurfaceVariant'));
  return c;
}
// Per tone: the headline, the sentence under it and the three facts.
const SUMMARY = {
  Ok: ['Connected to Maya', 'Messages travel directly between your devices', [['Path', 'Direct'], ['Round trip', '42 ms'], ['Peers', '6']]],
  Warning: ['Waiting for Maya', 'The network is still starting. Messages are kept and sent once Maya is reachable.', [['Path', 'None yet'], ['Round trip', 'No data'], ['Peers', '0']]],
  Error: ['Mosh cannot reach the network', 'The network runtime stopped. Restart Mosh to connect again.', [['Path', 'None'], ['Round trip', 'No data'], ['Peers', '0']]],
};
display(await grid('Summary card', ONE, axis('Tone', Object.keys(SUMMARY)), ({ Tone }) => {
  const [title, line, list] = SUMMARY[Tone];
  const c = inset('Summary card', { component: true, dir: 'V', gap: 3, pad: 4, w: 320, r: 'large', align: 'MIN' });
  add(c, inst('Status badge', { Tone }));
  const head = add(c, box('text', { dir: 'V', gap: 1, align: 'MIN' }), { fillW: true });
  para(head, title, 'titleMedium', 'onSurface', 'title');
  para(head, line, 'bodySmall', 'onSurfaceVariant', 'line');
  const cells = add(c, box('facts', { dir: 'H', gap: 4, align: 'MIN' }), { fillW: true });
  list.forEach(([label, value]) => add(cells, cell(label, value), { fillW: true }));
  return c;
}));

const EVENTS = [['09:42:25', 'peer_rtt', 'peer=7f3a9c21 ms=42'], ['09:42:08', 'message_delivered', 'id=m-2041'], ['09:41:51', 'relay_changed', 'from=none to=eu-west-2'], ['09:41:17', 'peer_joined', 'peer=7f3a9c21']];
const events = display(await grid('Event row', ONE, axis('Tone', ['Default', 'Accent']), ({ Tone }) => {
  const r = box('Event row', { component: true, dir: 'H', gap: 3, pad: [1, 0], w: 320, align: 'MIN' });
  add(r, text('09:42:25', 'labelSmall', 'onSurfaceMuted', { name: 'time' }));
  const col = add(r, box('event', { dir: 'V', align: 'MIN' }), { fillW: true });
  add(col, text('peer_rtt', 'labelMedium', Tone === 'Accent' ? 'primary' : 'onSurface', { name: 'event name', truncate: true }), { fillW: true });
  add(col, text('peer=7f3a9c21 ms=42', 'bodySmall', 'onSurfaceVariant', { name: 'detail', truncate: true }), { fillW: true });
  return r;
}));
prop(events, 'Time', 'TEXT', '09:42:25', 'time');
prop(events, 'Event', 'TEXT', 'peer_rtt', 'event name');
prop(events, 'Detail', 'TEXT', 'peer=7f3a9c21 ms=42', 'detail');

/** A named group of diagnostics; fill(group) adds what it holds. */
function group(parent, title, fill) {
  const g = add(parent, box(title, { dir: 'V', gap: 1, align: 'MIN' }), { fillW: true });
  add(add(g, box('label', { dir: 'H', pad: [0, 0, 1, 0] })), text(title, 'labelLarge', 'onSurfaceMuted'));
  add(g, inst('Divider', { Orientation: 'Horizontal' }), { fillW: true });
  fill(g);
  return g;
}
/** Connection status; Tone picks the summary, and what stands in for the values when there are none. */
function status({ Tone, Device }) {
  const d = surface('Connection status', 'panel', { component: true, dir: 'V', w: PANEL[Device], align: 'MIN' });
  panelHead(d, 'Connection status', Device, ['refresh', 'close']);
  const body = add(d, box('body', { dir: 'V', gap: 6, pad: [0, 5, 6, 5], align: 'MIN' }), { fillW: true });
  add(body, inst('Summary card', { Tone }), { fillW: true });
  if (Tone === 'Error') { add(body, setProps(inst('Inline error'), { Message: 'moss runtime exited: address already in use (port 41641)' }), { fillW: true }); return d; }
  group(body, 'Session', (g) => [['Role', 'Inviter'], ['Display name', 'Alex Rivera'], ['Session', 'maya']].forEach((r) => row(g, Device, r)));
  group(body, 'Moss network', (g) => {
    if (Tone === 'Warning') { add(add(g, box('empty', { dir: 'H', pad: [3, 0] })), text('Values appear when the network has started', 'bodySmall', 'onSurfaceMuted')); return; }
    const metrics = add(g, box('metrics', { dir: 'H', gap: 4, pad: [2, 0], align: 'MIN' }), { fillW: true });
    [['Peers', '6', '4 direct, 2 relayed'], ['NAT', 'Port-restricted', 'Reported type'], ['Relay', '1 active', '3 capable']].forEach((m) => add(metrics, cell(...m), { fillW: true }));
    [['Advertised', '198.51.100.23:41641'], ['Listen port', '41641'], ['Mesh id', 'mesh-4f2a91c07b3e'], ['Library version', '0.9.3']].forEach((r) => row(g, Device, r));
  });
  group(body, 'Moss events', (g) => EVENTS.forEach(([Time, Event, Detail], i) => add(g, setProps(inst('Event row', { Tone: i === 3 ? 'Accent' : 'Default' }), { Time, Event, Detail }), { fillW: true })));
  return d;
}
display(await grid('Connection status', axis('Tone', Object.keys(SUMMARY)), DEVICES, status));
