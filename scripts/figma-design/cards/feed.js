// Rows of the feed that are not messages: ConversationDateDivider,
// ConversationUnreadDivider, CallLogEntry and the notice a group posts about itself.
card('Feed rows', 'Between the messages the feed marks a new day, the first unread message, a call and a change to the group. They span the feed and stay quieter than a bubble; a call sits on the side of whoever made it.');
const SPAN = 480;
await grid('Date divider', ONE, ONE, () => {
  const c = box('Date divider', { component: true, dir: 'H', w: SPAN, pad: [3, 0, 2, 0], justify: 'CENTER' });
  const chip = add(c, box('chip', { dir: 'H', pad: [1, 3], r: 'full', fill: 'surfaceContainerHigh' }));
  add(chip, text('Sat, Nov 21', 'labelMedium', 'onSurfaceVariant', { name: 'date' }));
  return c;
}).then((set) => prop(set, 'Date', 'TEXT', 'Sat, Nov 21', 'date'));
await grid('Unread divider', ONE, ONE, () => {
  const c = box('Unread divider', { component: true, dir: 'H', w: SPAN, gap: 3, pad: [2, 0] });
  const line = () => add(c, rect('line', { fill: 'outlineVariant', w: 40, h: 1 }), { fillW: true });
  line();
  add(c, text('Unread messages', 'labelMedium', 'primary'));
  line();
  return c;
});
await grid('Group notice', ONE, ONE, () => {
  const c = box('Group notice', { component: true, dir: 'V', w: SPAN, pad: [2, 0] });
  const t = add(c, text('Leo Park changed the group name to Weekend plans', 'labelMedium', 'onSurfaceVariant', { name: 'notice', w: SPAN }), { fillW: true });
  t.textAlignHorizontal = 'CENTER';
  return c;
}).then((set) => prop(set, 'Notice', 'TEXT', 'Leo Park changed the group name to Weekend plans', 'notice'));

const CALLS = { Outgoing: ['call_made', 'Outgoing call', 'primary', 'secondaryContainer'], Incoming: ['call_received', 'Incoming call', 'primary', 'secondaryContainer'], Missed: ['call_missed', 'Missed call', 'error', 'errorContainer'] };
const calls = await grid('Call log entry', ONE, axis('Direction', Object.keys(CALLS)), ({ Direction }) => {
  const [glyph, title, ink, plate] = CALLS[Direction];
  const c = box('Call log entry', { component: true, dir: 'H', gap: 3, pad: [2, 4, 2, 2], r: 'largeIncreased', fill: 'incoming' });
  const p = add(c, box('plate', { dir: 'H', wk: 8, hk: 8, r: 'full', fill: plate, justify: 'CENTER' }));
  add(p, icon(glyph, ink, 4));
  const col = add(c, box('call', { dir: 'V', align: 'MIN' }));
  add(col, text(title, 'labelLarge', 'onSurface'));
  // A missed call has no length to show.
  if (Direction !== 'Missed') add(col, text('12:34', 'labelMedium', 'onSurfaceMuted', { name: 'detail' }));
  add(c, text('18:20', 'labelSmall', 'onSurfaceMuted', { name: 'time' }));
  return c;
});
prop(calls, 'Detail', 'TEXT', '12:34', 'detail');
prop(calls, 'Time', 'TEXT', '18:20', 'time');
