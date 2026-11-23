// Rows of the feed that are not messages: ConversationDateDivider,
// ConversationUnreadDivider, CallLogEntry and the notice a group posts about itself.
card('Feed rows', 'Between the messages the feed marks a new day, the first unread message, a call and a change to the group. They span the feed and stay quieter than a bubble; a call sits on the side of whoever made it, in the bubble colour of that side.');
const SPAN = MEASURE.Desktop;
const dates = await grid('Date divider', ONE, ONE, () => {
  const c = box('Date divider', { component: true, dir: 'H', w: SPAN, pad: [3, 0, 2, 0], justify: 'CENTER' });
  const chip = add(c, box('chip', { dir: 'H', pad: [1, 3], r: 'full', fill: 'surfaceContainerHigh' }));
  add(chip, text('Sat, Nov 21', 'labelMedium', 'onSurfaceVariant', { name: 'date' }));
  return c;
});
prop(dates, 'Date', 'TEXT', 'Sat, Nov 21', 'date');
await grid('Unread divider', ONE, ONE, () => {
  const c = box('Unread divider', { component: true, dir: 'H', w: SPAN, gap: 3, pad: [2, 0] });
  add(c, inst('Divider', { Orientation: 'Horizontal' }), { fillW: true });
  add(c, text('Unread messages', 'labelMedium', 'primary'));
  add(c, inst('Divider', { Orientation: 'Horizontal' }), { fillW: true });
  return c;
});
const notices = await grid('Group notice', ONE, ONE, () => {
  const c = box('Group notice', { component: true, dir: 'V', w: SPAN, pad: [2, 0] });
  const t = add(c, text('Leo Park changed the group name to Weekend plans', 'labelMedium', 'onSurfaceVariant', { name: 'notice', w: SPAN }), { fillW: true });
  t.textAlignHorizontal = 'CENTER';
  return c;
});
prop(notices, 'Notice', 'TEXT', 'Leo Park changed the group name to Weekend plans', 'notice');

// The arrow tells who rang and, in the error colour, that nobody answered; the handset rings back.
// Per direction: the arrow, the title, the bubble it sits in and the ink of the arrow.
const CALLS = { Outgoing: ['call_made', 'Outgoing call', 'Outgoing', 'accent'], Incoming: ['call_received', 'Incoming call', 'Surface', 'accent'], Missed: ['call_received', 'Missed call', 'Surface', 'error'] };
const calls = await grid('Call log entry', ONE, axis('Direction', Object.keys(CALLS)), ({ Direction }) => {
  // A call the user made is theirs, like a message they sent, and takes the outgoing bubble's colour and inks.
  const [glyph, title, Tone, mark] = CALLS[Direction], tone = TONES[Tone];
  const c = box('Call log entry', { component: true, dir: 'H', gap: 6, pad: [2, 3, 2, 4], r: 'largeIncreased', fill: Tone === 'Outgoing' ? 'outgoing' : 'incoming' });
  const col = add(c, box('call', { dir: 'V', align: 'MIN' }));
  add(col, text(title, 'labelLarge', tone.ink));
  const meta = add(col, box('meta', { dir: 'H', gap: 1 }));
  add(meta, icon(glyph, tone[mark], 4));
  // A missed call has no length to show, only when it rang.
  const missed = Direction === 'Missed';
  add(meta, text(missed ? '18:26' : '18:26, 2 min 5 s', 'labelMedium', tone.quiet, { name: missed ? 'rang' : 'detail' }));
  add(c, icon('call', tone.accent, 6));
  return c;
});
prop(calls, 'Detail', 'TEXT', '18:26, 2 min 5 s', 'detail');
prop(calls, 'Detail, missed', 'TEXT', '18:26', 'rang');
