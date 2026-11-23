// Messages: ConversationMessageRow with its text, footer, DeliveryTicks and
// FailedMessageRetry, and the sender line of groups and channels.
card('Message', 'A bubble hugs its text and wraps it at a fixed measure, 480 px on the desktop and 232 px on the phone, so a long link or a token without spaces breaks inside it. The time ends the last line of the text; when that line is full it drops to a row of its own. A file, a picture or a voice message rides above the text, or stands in for it; the text under it is a caption and wraps at its width; a file or a voice message alone keeps the time in its own last line. In a run from one sender the corners on the sender\'s side tighten, and only the first bubble carries the sender. A direct chat shows no avatar; a group and a channel show it beside the first bubble and keep its gutter under it.');
// The clock stands for a message that is queued or on its way. Read is told from delivered by a heavier, darker pair of ticks: on the saffron bubble a colour alone is too close.
// Each of the paired ticks is drawn smaller than a lone one, so the lone tick and the clock are set a step down and every mark reads the same size beside the time.
const TICKS = { Queued: ['schedule', 'onOutgoingVariant', 3], Sent: ['check', 'onOutgoingVariant', 3], Delivered: ['done_all', 'onOutgoingVariant', 4], Read: ['done_all_read', 'onOutgoing', 4] };
const tickSet = await grid('Delivery ticks', ONE, axis('State', Object.keys(TICKS)), ({ State }) => {
  const c = box('Delivery ticks', { component: true, dir: 'H', wk: 4, hk: 4, justify: 'CENTER' });
  add(c, icon(...TICKS[State]));
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
  // The bubble's own padding is the same on every side, so an attachment's 12 px corners stay concentric with its 20 px ones; text is set in a little further.
  const INSET = [0, 1, 0, 2];
  const bubble = add(root, box('bubble', { dir: 'V', gap: 1, pad: 2, fill: gone ? null : out ? 'outgoing' : 'incoming', stroke: gone ? 'outlineVariant' : null, align: 'MIN', clip: true }));
  corners(bubble, out, Position);
  if (!out) {
    const sender = add(bubble, box('sender', { dir: 'H', gap: 2, pad: INSET }));
    add(sender, text('Priya Nair', 'labelLargeEmphasized', 'onSurface', { name: 'sender name', cut: true }), { max: MEASURE[Device] - 96 });
    add(add(sender, box('fingerprint chip', { dir: 'H', pad: [0, 1], r: 'extraSmall', fill: 'surfaceContainerHighest' })), text('5b80f2…7d36', 'labelSmall', 'onSurfaceVariant', { name: 'fingerprint' }));
  }
  if (gone) {
    const note = add(bubble, box('deleted', { dir: 'V', pad: INSET, align: 'MIN' }));
    add(note, text('Message deleted', 'bodyLarge', quiet));
    if (State === 'Awaiting deletion') add(note, text('Awaiting deletion', 'labelMedium', quiet));
    return root;
  }
  // A file, a picture or a voice message rides above the text; swap the instance for another kind.
  add(bubble, inst('File card', { State: 'Ready', Tone: out ? 'Outgoing' : 'Surface', Device })).name = 'attachment';
  // The time is pinned to the bubble's far corner, so it stays there under a wider attachment. An unpainted
  // copy of it follows the text and keeps the text clear of it: beside a short text, on a row of its own
  // when the text fills the measure. Where the last of several lines leaves room, the copy is switched off
  // and the time sits in that line.
  // Under an attachment the text is a caption, which wraps at the attachment's width; an instance cannot
  // narrow its own line, so the caption is a second line that takes the place of the first.
  for (const [name, width] of [['line', lineWidth(Device)], ['caption', attachmentWidth(Device)]]) {
    const line = add(bubble, box(name, { dir: 'H', gap: 2, pad: INSET, align: 'MAX' }), { max: width });
    line.layoutWrap = 'WRAP'; line.visible = name === 'line';
    add(add(line, box('body', { dir: 'H' })), text('Should we leave at 6 to beat the traffic?', 'bodyLarge', ink, { name: 'text' }), { max: width - lineWidth(Device) + MEASURE[Device] });
    const room = add(line, box('room for the time', { dir: 'H', gap: 1 }));
    add(room, text('08:31', 'labelSmall', quiet, { name: 'time' })).fills = [];
    if (out) add(room, box('room for the mark', { dir: 'H', wk: 4, hk: 4 }));
  }
  const meta = add(bubble, box('meta', { dir: 'H', gap: 1 }), { abs: [0, 0] });
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
  meta.x = bubble.width - meta.width - px('space/3'); meta.y = bubble.height - meta.height - px('space/2');
  meta.constraints = { horizontal: 'MAX', vertical: 'MAX' };
  return root;
}
const POSITIONS = perDevice(axis('Position', ['Single', 'First', 'Middle', 'Last']));
const incoming = display(await grid('Incoming message', POSITIONS, axis('State', ['Default', 'Deleted']), (p) => message('Incoming', p)));
const outgoing = display(await grid('Outgoing message', POSITIONS, axis('State', ['Default', 'Failed', 'Deleted', 'Awaiting deletion']), (p) => message('Outgoing', p)));
for (const set of [incoming, outgoing]) {
  prop(set, 'Text', 'TEXT', 'Should we leave at 6 to beat the traffic?', 'text');
  prop(set, 'Time', 'TEXT', '08:31', 'time');
  prop(set, 'Show text', 'BOOLEAN', true, 'body');
  // Off for a file or a voice message alone: the time then sits in the attachment's own last line instead of a line of its own.
  prop(set, 'Text line', 'BOOLEAN', true, 'line');
  prop(set, 'Attachment', 'BOOLEAN', false, 'attachment');
  // On with a text under an attachment, and then 'Text line' is off.
  prop(set, 'Caption', 'BOOLEAN', false, 'caption');
  // Off where the last of several lines has room for the time.
  prop(set, 'Room for the time', 'BOOLEAN', true, 'room for the time');
}
prop(outgoing, 'Reason', 'TEXT', 'Not sent', 'reason');
prop(incoming, 'Sender', 'BOOLEAN', false, 'sender');
prop(incoming, 'Sender name', 'TEXT', 'Priya Nair', 'sender name');
prop(incoming, 'Fingerprint', 'TEXT', '5b80f2…7d36', 'fingerprint');
prop(incoming, 'Gutter', 'BOOLEAN', false, 'gutter');
prop(incoming, 'Avatar', 'BOOLEAN', true, 'avatar');
