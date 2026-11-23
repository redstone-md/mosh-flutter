// Avatar: Avatar, ConversationKindAvatar and UserPlusBadge.
card('Avatar', 'A person shows initials, a group and a channel show their sign. The plate is one of four muted colours picked per contact. Compact sits beside a message and in a roster, small in an invitation, medium in the chat list, large on a profile. Presence and the Mosh+ mark switch on as properties.');
// Per size: the plate's edge as a space key, the initials' text style, the sign's and the presence dot's size keys.
const SIZES = { Compact: [8, 'labelMedium', 4, 3], Small: [10, 'titleSmall', 5, 3], Medium: [12, 'titleMedium', 6, 3], Large: [16, 'headlineSmall', 8, 4] };
await grid('Mosh+ badge', ONE, axis('Tone', ['Accent', 'Plain', 'Muted']), ({ Tone }) => {
  const b = box('Mosh+ badge', { component: true, dir: 'H' });
  add(b, icon('plus_badge', { Accent: 'primary', Plain: 'onSurface', Muted: 'onSurfaceVariant' }[Tone], 4));
  return b;
});
function avatar({ Kind, Plate, Size }) {
  const [key, initials, sign, presenceKey] = SIZES[Size];
  const a = box('Avatar', { component: true, dir: 'H', wk: key, hk: key, justify: 'CENTER' });
  const plate = add(a, box('plate', { dir: 'H', wk: key, hk: key, r: 'full', fill: 'avatar' + Plate, justify: 'CENTER', clip: true }));
  if (Kind === 'Person') add(plate, text('MC', initials, 'onAvatar', { name: 'initials' }));
  else add(plate, icon(Kind === 'Group' ? 'group' : 'tag', 'onAvatar', sign));
  const edge = px('space/' + key);
  const presence = add(a, dot('presence', 'success', presenceKey), { abs: [0, 0] });
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
const set = await grid('Avatar', rows, axis('Size', Object.keys(SIZES)), avatar);
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
