// Messages: ConversationMessageRow with its text, footer, DeliveryTicks and
// FailedMessageRetry, and the sender line of groups and channels.
card('Message', 'A bubble hugs its text and wraps it at a fixed measure, 480 px on the desktop and 232 px on the phone, so a long link or a token without spaces breaks inside it. In a run from one sender the corners on the sender\'s side tighten, and only the first bubble carries the sender. A direct chat shows no avatar; a group and a channel show it beside the first bubble and keep its gutter under it.');
// Read is told from delivered by a heavier, darker pair of ticks: on the saffron bubble a colour alone is too close.
const TICKS = { Queued: ['schedule', 'onOutgoingVariant'], Sent: ['check', 'onOutgoingVariant'], Delivered: ['done_all', 'onOutgoingVariant'], Read: ['done_all_read', 'onOutgoing'] };
const ticks = await grid('Delivery ticks', ONE, axis('State', Object.keys(TICKS)), ({ State }) => {
  const c = box('Delivery ticks', { component: true, dir: 'H' });
  add(c, icon(...TICKS[State], 4));
  return c;
}, 64);
// The ticks are drawn for the outgoing bubble, so the set shows them on its colour.
ticks.fills = paint('outgoing'); radius(ticks, 'medium');

const MEASURE = { Desktop: 480, Phone: 232 };
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
  const root = box(side + ' message', { component: true, dir: 'H', gap: 2, align: 'MIN' });
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
    add(sender, text('5b80f2…7d36', 'labelSmall', 'onSurfaceMuted', { name: 'fingerprint' }));
  }
  if (gone) {
    add(body, text('Message deleted', 'bodyLarge', quiet, { name: 'deleted' }));
    if (State === 'Awaiting deletion') add(body, text('Awaiting deletion', 'labelMedium', quiet, { name: 'deletion' }));
    return root;
  }
  add(body, text('Should we leave at 6 to beat the traffic?', 'bodyLarge', ink, { name: 'text' }), { max: MEASURE[Device] });
  const meta = add(bubble, box('meta', { dir: 'H', gap: 1 }));
  add(meta, text('08:31', 'labelSmall', quiet, { name: 'time' }));
  if (State === 'Failed') {
    const failed = add(body, box('failed', { dir: 'H', gap: 3 }));
    add(failed, text('peer unreachable', 'labelMedium', 'outgoingError', { name: 'reason' }));
    // Retry is pressed on its own, so on the phone it holds a 48 px target.
    const retry = add(failed, box('retry', { dir: 'H', minHk: Device === 'Phone' ? 12 : null, minWk: Device === 'Phone' ? 12 : null, justify: 'CENTER' }));
    add(retry, text('Retry', 'labelLarge', 'outgoingError'));
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
}
prop(outgoing, 'Reason', 'TEXT', 'peer unreachable', 'reason');
prop(incoming, 'Sender', 'BOOLEAN', false, 'sender');
prop(incoming, 'Sender name', 'TEXT', 'Priya Nair', 'sender name');
prop(incoming, 'Fingerprint', 'TEXT', '5b80f2…7d36', 'fingerprint');
prop(incoming, 'Gutter', 'BOOLEAN', false, 'gutter');
prop(incoming, 'Avatar', 'BOOLEAN', true, 'avatar');
