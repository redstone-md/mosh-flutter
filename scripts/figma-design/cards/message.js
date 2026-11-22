// Messages: ConversationMessageRow with its text, footer, DeliveryTicks and
// FailedMessageRetry, and the sender line of groups and channels.
card('Message', 'A bubble hugs its text and wraps it at a fixed measure, 480 px on the desktop and 232 px on the phone, so a long link or a token without spaces breaks inside it. A file, a picture or a voice message rides above the text, or stands in for it. In a run from one sender the corners on the sender\'s side tighten, and only the first bubble carries the sender. A direct chat shows no avatar; a group and a channel show it beside the first bubble and keep its gutter under it.');
// The clock stands for a message that is queued or on its way. Read is told from delivered by a heavier, darker pair of ticks: on the saffron bubble a colour alone is too close.
const TICKS = { Queued: ['schedule', 'onOutgoingVariant'], Sent: ['check', 'onOutgoingVariant'], Delivered: ['done_all', 'onOutgoingVariant'], Read: ['done_all_read', 'onOutgoing'] };
const tickSet = await grid('Delivery ticks', ONE, axis('State', Object.keys(TICKS)), ({ State }) => {
  const c = box('Delivery ticks', { component: true, dir: 'H' });
  add(c, icon(...TICKS[State], 4));
  return c;
}, 64);
// The ticks are drawn for the outgoing bubble, so the set shows them on its colour.
tickSet.fills = paint('outgoing'); radius(tickSet, 'medium');

const ROUND = 'largeIncreased', TIGHT = 'small';
/** Corner radii of a bubble at its place in a run: the sender's side tightens between neighbours. */
function corners(bubble, out, position) {
  const top = position === 'Single' || position === 'First' ? ROUND : TIGHT;
  const bottom = position === 'Single' || position === 'Last' ? ROUND : TIGHT;
  const names = out ? [ROUND, top, bottom, ROUND] : [top, ROUND, ROUND, bottom];
  ['topLeftRadius', 'topRightRadius', 'bottomRightRadius', 'bottomLeftRadius'].forEach((f, i) => bind(bubble, f, 'radius/' + names[i]));
}
/** One variant of a message. side: 'Incoming' | 'Outgoing'. */
function message(side, { Position, Device, State }) {
  const out = side === 'Outgoing', ink = out ? 'onOutgoing' : 'onSurface';
  // An incoming message is a row, gutter then bubble; an outgoing one a column, so a failure can sit under its bubble.
  const root = box(side + ' message', out ? { component: true, dir: 'V', align: 'MAX' } : { component: true, dir: 'H', gap: 2, align: 'MIN' });
  if (!out) {
    const gutter = add(root, box('gutter', { dir: 'H', wk: 8, align: 'MIN' }));
    add(gutter, inst('Avatar', { Kind: 'Person', Plate: '1', Size: 'Compact' })).name = 'avatar';
  }
  // A deleted message keeps its place in the run but gives up its colour: an outline and quiet text.
  const gone = State === 'Deleted' || State === 'Awaiting deletion', quiet = out && !gone ? 'onOutgoingVariant' : 'onSurfaceMuted';
  const bubble = add(root, box('bubble', { dir: 'H', gap: 2, pad: [2, 3, 2, 4], fill: gone ? null : out ? 'outgoing' : 'incoming', stroke: gone ? 'outlineVariant' : null, align: 'MAX', clip: true }));
  corners(bubble, out, Position);
  const body = add(bubble, box('body', { dir: 'V', gap: 1, align: 'MIN' }));
  if (!out) {
    const sender = add(body, box('sender', { dir: 'H', gap: 2 }));
    add(sender, text('Priya Nair', 'labelLarge', 'onSurface', { name: 'sender name', cut: true }), { max: MEASURE[Device] - 96 });
    add(add(sender, box('fingerprint chip', { dir: 'H', pad: [0, 1], r: 'extraSmall', fill: 'surfaceContainerHighest' })), text('5b80f2…7d36', 'labelSmall', 'onSurfaceVariant', { name: 'fingerprint' }));
  }
  if (gone) {
    add(body, text('Message deleted', 'bodyLarge', quiet, { name: 'deleted' }));
    if (State === 'Awaiting deletion') add(body, text('Awaiting deletion', 'labelMedium', quiet, { name: 'deletion' }));
    return root;
  }
  // A file, a picture or a voice message rides above the text; swap the instance for another kind.
  add(body, inst('File card', { State: 'Ready', Tone: out ? 'Outgoing' : 'Surface', Device })).name = 'attachment';
  add(body, text('Should we leave at 6 to beat the traffic?', 'bodyLarge', ink, { name: 'text' }), { max: MEASURE[Device] });
  const meta = add(bubble, box('meta', { dir: 'H', gap: 1 }));
  add(meta, text('08:31', 'labelSmall', quiet, { name: 'time' }));
  if (State === 'Failed') {
    // The bubble keeps its colour and marks the failure where the ticks would be; the notice and the way out sit under it, on the feed.
    add(meta, icon('error_fill', 'outgoingError', 4));
    const failed = add(root, box('failed', { dir: 'H', gap: 1 }));
    add(failed, text('Not sent', 'labelMedium', 'error', { name: 'reason', cut: true }), { max: MEASURE[Device] - 64 });
    // Only the failure is red; the way out is in the feed's own ink.
    const retry = add(failed, setProps(inst('Button', { Kind: 'Text', Device, State: 'Default' }), { Label: 'Retry' }));
    retry.name = 'retry'; retry.findOne((n) => n.type === 'TEXT').fills = paint('onSurface');
  } else if (out) {
    const ticks = add(meta, inst('Delivery ticks', { State: 'Delivered' }));
    ticks.name = 'ticks'; ticks.isExposedInstance = true;
  }
  return root;
}
const POSITIONS = perDevice(axis('Position', ['Single', 'First', 'Middle', 'Last']));
const incoming = display(await grid('Incoming message', POSITIONS, axis('State', ['Default', 'Deleted']), (p) => message('Incoming', p)));
const outgoing = display(await grid('Outgoing message', POSITIONS, axis('State', ['Default', 'Failed', 'Deleted', 'Awaiting deletion']), (p) => message('Outgoing', p)));
for (const set of [incoming, outgoing]) {
  prop(set, 'Text', 'TEXT', 'Should we leave at 6 to beat the traffic?', 'text');
  prop(set, 'Time', 'TEXT', '08:31', 'time');
  prop(set, 'Show text', 'BOOLEAN', true, 'text');
  prop(set, 'Attachment', 'BOOLEAN', false, 'attachment');
}
prop(outgoing, 'Reason', 'TEXT', 'Not sent', 'reason');
prop(incoming, 'Sender', 'BOOLEAN', false, 'sender');
prop(incoming, 'Sender name', 'TEXT', 'Priya Nair', 'sender name');
prop(incoming, 'Fingerprint', 'TEXT', '5b80f2…7d36', 'fingerprint');
prop(incoming, 'Gutter', 'BOOLEAN', false, 'gutter');
prop(incoming, 'Avatar', 'BOOLEAN', true, 'avatar');
