// Avatar: Avatar, ConversationKindAvatar and UserPlusBadge.
card('Avatar', 'A person shows initials, a group and a channel show their sign. The plate is one of four muted colours picked per contact. Small is for lists and headers, large for a profile. Presence and the Mosh+ mark switch on as properties.');
await grid('Mosh+ badge', ONE, axis('Tone', ['Accent', 'Plain', 'Muted']), ({ Tone }) => {
  const b = box('Mosh+ badge', { component: true, dir: 'H' });
  add(b, icon('plus_badge', { Accent: 'primary', Plain: 'onSurface', Muted: 'onSurfaceVariant' }[Tone], 4));
  return b;
});
function avatar({ Kind, Plate, Size }) {
  const big = Size === 'Large', key = big ? 16 : 10;
  const a = box('Avatar', { component: true, dir: 'H', wk: key, hk: key, justify: 'CENTER' });
  const plate = add(a, box('plate', { dir: 'H', wk: key, hk: key, r: 'full', fill: 'avatar' + Plate, justify: 'CENTER', clip: true }));
  if (Kind === 'Person') add(plate, text('MC', big ? 'headlineSmall' : 'titleSmall', 'onAvatar', { name: 'initials' }));
  else add(plate, icon(Kind === 'Group' ? 'group' : 'tag', 'onAvatar', big ? 8 : 5));
  const edge = px('space/' + key);
  const presence = add(a, dot('presence', 'success', big ? 4 : 3), { abs: [0, 0] });
  stroke(presence, 'surface', 'thick', 'OUTSIDE');
  // Both marks sit on the circle's edge, on its diagonals.
  const inset = (edge / 2) * (1 - Math.SQRT1_2);
  presence.x = presence.y = Math.round(edge - inset - presence.width / 2);
  presence.constraints = { horizontal: 'MAX', vertical: 'MAX' };
  const mark = add(a, box('Mosh+', { dir: 'H', r: 'full', fill: 'surface' }), { abs: [0, 0] });
  add(mark, inst('Mosh+ badge', { Tone: 'Accent' }));
  mark.x = Math.round(edge - inset - mark.width / 2); mark.y = Math.round(inset - mark.height / 2);
  mark.constraints = { horizontal: 'MAX', vertical: 'MIN' };
  return a;
}
const rows = ['Person', 'Group', 'Channel'].flatMap((k) => ['1', '2', '3', '4'].map((p) => [`${k}, plate ${p}`, { Kind: k, Plate: p }]));
const set = await grid('Avatar', rows, axis('Size', ['Small', 'Large']), avatar);
prop(set, 'Initials', 'TEXT', 'MC', 'initials');
prop(set, 'Presence', 'BOOLEAN', false, 'presence');
prop(set, 'Mosh+', 'BOOLEAN', false, 'Mosh+');
const shown = (props, values) => setProps(inst('Avatar', props), values);
await examples('Online, with Mosh+, group and channel', [
  shown({ Kind: 'Person', Plate: '2', Size: 'Small' }, { Presence: true }),
  shown({ Kind: 'Person', Plate: '4', Size: 'Small' }, { Initials: 'LP', Presence: true, 'Mosh+': true }),
  shown({ Kind: 'Group', Plate: '1', Size: 'Small' }, {}),
  shown({ Kind: 'Channel', Plate: '3', Size: 'Small' }, {}),
  shown({ Kind: 'Person', Plate: '1', Size: 'Large' }, { Initials: 'AR', 'Mosh+': true }),
]);
