// The organisation section of the chat list: OrgSection with its header
// (org_section._Header), member rows (_MemberRow), offers (_OfferRow, drawn by
// the Invitation row) and the new-group form (_NewGroupForm).
card('Organisation', 'A member of an organisation sees its people under the chats: who is in it, who wants to talk, and a field to start a group with them. While a change is on its way the section is busy and its controls wait. Until the list of members arrives the section says so.');
const ROW = { Desktop: 324, Phone: 358 };
const DEVICES = axis('Device', ['Desktop', 'Phone']);
const headers = await grid('Organisation header', axis('State', ['Default', 'Busy']), DEVICES, ({ State, Device }) => {
  const h = box('Organisation header', { component: true, dir: 'H', gap: 2, pad: [0, 0, 0, 3], w: ROW[Device], minHk: 12 });
  add(h, icon('organisation', 'onSurfaceMuted', 4));
  add(h, text('Northwind Studio', 'labelLarge', 'onSurfaceMuted', { name: 'name', truncate: true }), { fillW: true });
  add(h, action('close', Device, { State: State === 'Busy' ? 'Disabled' : 'Default' })).name = 'leave';
  return h;
});
prop(headers, 'Name', 'TEXT', 'Northwind Studio', 'name');

const members = display(await grid('Member row', ONE, DEVICES, ({ Device }) => {
  const r = box('Member row', { component: true, dir: 'H', gap: 3, pad: [1, 3], w: ROW[Device], minHk: Device === 'Phone' ? 12 : 10 });
  const avatar = add(r, inst('Avatar', { Kind: 'Person', Plate: '2', Size: 'Compact' }));
  avatar.name = 'avatar'; avatar.isExposedInstance = true;
  const col = add(r, box('text', { dir: 'V', align: 'MIN' }), { fillW: true });
  add(col, text('Maya Chen', 'labelLarge', 'onSurface', { name: 'name', truncate: true }), { fillW: true });
  add(col, text('peer-m…08de', 'labelSmall', 'onSurfaceMuted', { name: 'peer', truncate: true }), { fillW: true });
  add(r, icon('admin', 'onSurfaceVariant', 4)).name = 'admin';
  return r;
}));
prop(members, 'Name', 'TEXT', 'Maya Chen', 'name');
prop(members, 'Peer', 'TEXT', 'peer-m…08de', 'peer');
prop(members, 'Show peer', 'BOOLEAN', true, 'peer');
prop(members, 'Admin', 'BOOLEAN', false, 'admin');

await grid('New group form', axis('State', ['Default', 'Busy']), DEVICES, ({ State, Device }) => {
  const off = State === 'Busy' ? 'Disabled' : 'Default';
  const f = box('New group form', { component: true, dir: 'H', gap: 1, pad: [1, 0, 1, 3], w: ROW[Device], minHk: 12 });
  add(f, setProps(inst('Text field', { Device, State: off }), { 'Show label': false, Placeholder: 'Group name', Value: 'Group name' }), { fillW: true });
  add(f, action('add', Device, { State: off }));
  return f;
});
await grid('Roster notice', ONE, ONE, () => {
  const n = box('Roster notice', { component: true, dir: 'H', gap: 3, pad: [3, 3], w: ROW.Desktop });
  add(n, inst('Circular progress', { Size: 'Small' }));
  add(n, text('Waiting for the list of members', 'bodySmall', 'onSurfaceVariant'));
  return n;
});

const PEOPLE = [['Alex (you)', 'peer-a…3a92', 'A', '1', true], ['Maya Chen', 'peer-m…08de', 'MC', '2', true], ['Leo Park', 'peer-l…71aa', 'LP', '4', false], ['Bartholomew Featherstonehaugh-Cholmondeley', 'peer-b…e77b', 'BF', '3', false]];
/** The section on [Device] in one of its states: 'Roster' | 'Busy' | 'Waiting'. */
function section(state, Device) {
  const s = box(`${state} · ${Device}`, { dir: 'V', pad: [2, 2], w: ROW[Device] + 16, fill: 'surfaceContainerLow', align: 'MIN' });
  const State = state === 'Busy' ? 'Busy' : 'Default';
  add(s, inst('Organisation header', { State, Device }), { fillW: true });
  if (state === 'Waiting') { add(s, inst('Roster notice'), { fillW: true }); return s; }
  if (state === 'Roster') {
    const ask = add(s, setProps(inst('Invitation row', { Device }), { Title: 'Daniel Kim', Detail: 'wants to chat' }), { fillW: true });
    setProps(ask.findOne((n) => n.name === 'avatar'), { Initials: 'DK' });
    const offer = add(s, setProps(inst('Invitation row', { Device }), { Title: 'Spring launch', Detail: 'Invited by Maya Chen' }), { fillW: true });
    offer.findOne((n) => n.name === 'avatar').swapComponent(variant('Avatar', { Kind: 'Group', Plate: '3', Size: 'Small' }));
  }
  add(s, inst('New group form', { State, Device }), { fillW: true });
  for (const [Name, Peer, Initials, Plate, Admin] of PEOPLE) {
    const row = add(s, setProps(inst('Member row', { Device }), { Name, Peer, Admin }), { fillW: true });
    const a = row.findOne((n) => n.name === 'avatar');
    a.swapComponent(variant('Avatar', { Kind: 'Person', Plate, Size: 'Compact' }));
    setProps(a, { Initials });
  }
  return s;
}
(await examples('Roster with two offers, busy, waiting for the roster', [section('Roster', 'Desktop'), section('Roster', 'Phone'), section('Busy', 'Desktop'), section('Waiting', 'Desktop')])).counterAxisAlignItems = 'MIN';
