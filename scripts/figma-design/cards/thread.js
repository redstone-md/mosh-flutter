// Threads assembled from the message and feed components, to judge the
// density of the feed and the rhythm of its runs on real conversations: the
// captured "Conversation / DM / Thread" and "Conversation / Group / Thread",
// then a feed of attachments and one of text that is hard to wrap.
card('Thread', 'The components in use. Bubbles of one run sit 4 px apart and a new run starts 12 px lower. The last example holds what a feed has to survive: a long link, a token without spaces and a long name.');
const DM = [
  { kind: 'call', direction: 'Outgoing', detail: '18:02, 3 min 7 s' },
  { kind: 'call', direction: 'Incoming', detail: '18:20, 12 min 34 s' },
  { kind: 'date', date: 'Sat, Nov 21' },
  { kind: 'unread' },
  { kind: 'in', text: 'Leo can drive. He has room for three and the gear.', time: '08:12' },
  { kind: 'in', text: 'I booked the cabin near the lighthouse for two nights.', time: '08:13' },
  { kind: 'out', text: 'Perfect. I will bring the camera and the thermos.', time: '08:30', ticks: 'Read' },
  { kind: 'out', text: 'Should we leave at 6 to beat the traffic?', time: '08:31', ticks: 'Delivered' },
  { kind: 'out', text: 'Sending the packing list in a minute.', time: '08:32', ticks: 'Sent' },
  { kind: 'out', text: 'Also, do you have a spare headlamp?', time: '08:33', ticks: 'Queued' },
  { kind: 'out', text: 'Here is the route I mapped out.', time: '08:34', state: 'Failed' },
];
const GROUP = [
  { kind: 'in', from: 'Leo Park', print: '7e19b0…2f41', plate: '4', text: 'Who is in for Saturday?', time: '19:00' },
  { kind: 'notice', notice: 'Leo Park changed the group name to Weekend plans' },
  { kind: 'in', from: 'Priya Nair', print: '5b80f2…7d36', plate: '3', text: 'Me! I can bring snacks and the big tent.', time: '19:04' },
  { kind: 'date', date: 'Sat, Nov 21' },
  { kind: 'unread' },
  { kind: 'in', from: 'Maya Chen', print: 'c4d2e8…b3e6', plate: '2', text: 'Count me in. The cabin is booked.', time: '08:15' },
  { kind: 'in', from: 'Maya Chen', print: 'c4d2e8…b3e6', plate: '2', text: 'Check-in is from 3 pm, keys are in the lockbox.', time: '08:16' },
  { kind: 'in', from: 'Maya Chen', state: 'Deleted' },
  { kind: 'out', text: 'Great, I will sort out the playlist for the drive.', time: '09:02', ticks: 'Read' },
  { kind: 'out', state: 'Awaiting deletion' },
  { kind: 'in', from: 'Leo Park', print: '7e19b0…2f41', plate: '4', text: 'Leaving at 6 sharp. Coffee is on me.', time: '09:20' },
];
const HARD = [
  { kind: 'in', from: 'Bartholomew Featherstonehaugh-Cholmondeley of the Outer Hebrides', print: 'a01f9c…e77b', plate: '1', text: 'The map is at https://maps.example.org/routes/coast/2026/november/lighthouse-loop?start=harbour&stops=cabin,viewpoint,cafe&share=7f3a9c1e', time: '10:02' },
  { kind: 'out', text: 'mosh1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlhmosh1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh', time: '10:03', ticks: 'Delivered' },
  { kind: 'out', text: 'ok', time: '10:03', ticks: 'Sent' },
];
// attach: [component set, its variant, its text properties, the file's name].
const FILES = [
  { kind: 'in', text: 'The route with all the stops', time: '08:15', attach: ['File card', { State: 'Transfer' }, { 'Detail, transfer': '58% of 1.2 MB' }, 'coast-route.pdf'] },
  { kind: 'in', time: '08:16', attach: ['File card', { State: 'To download' }, { 'Detail, to download': '24 MB' }, 'trail-map-with-every-waypoint-and-campsite-final-v3.zip'] },
  { kind: 'out', time: '08:20', ticks: 'Queued', attach: ['File card', { State: 'Failed' }, {}, 'packing-list.docx'] },
  { kind: 'out', text: 'Sunrise from the ridge, just before the fog rolled in over the bay', time: '09:06', ticks: 'Read', attach: ['Media card', { Kind: 'Image', State: 'Ready' }, {}, 'ridge-trail-at-sunrise-from-the-north-face.jpg'] },
  { kind: 'in', time: '10:02', attach: ['Voice message', { State: 'Idle' }, {}] },
  { kind: 'out', time: '10:04', ticks: 'Read', attach: ['Voice message', { State: 'Playing' }, {}] },
];
/** Width of the last line of the wrapped text [t]: a copy is cut shorter until it loses a line. */
function lastLineWidth(t) {
  const probe = text(t.characters, 'bodyLarge', 'onSurface');
  pendingText.pop();
  // Resizing a text fixes its height, so the copy is told to grow only after it.
  probe.resize(t.width, t.height); probe.textAutoResize = 'HEIGHT';
  const full = probe.height;
  let fits = 0, over = t.characters.length;
  while (over - fits > 1) {
    const mid = (fits + over) >> 1;
    probe.characters = t.characters.slice(0, mid);
    if (probe.height < full) fits = mid; else over = mid;
  }
  // The character at [fits] is the first to need the last line. It takes the start of its word down with it, unless the word is too long for a line and is broken there.
  const word = t.characters.lastIndexOf(' ', fits) + 1;
  probe.textAutoResize = 'WIDTH_AND_HEIGHT'; probe.characters = t.characters.slice(word, fits + 1);
  const from = probe.width <= t.width ? word : fits;
  probe.characters = t.characters.slice(from);
  const w = probe.width;
  probe.remove();
  return w;
}
/** Puts the time in the last line of a text of several lines when that line leaves room for it. */
function seatTime(b, caption) {
  const line = b.findOne((n) => n.name === 'bubble').children.find((n) => n.name === (caption ? 'caption' : 'line'));
  const t = line.findOne((n) => n.name === 'text'), room = line.findOne((n) => n.name === 'room for the time');
  // One line is a line height tall, which is under two font sizes; two lines are over.
  if (t.height < 2 * t.fontSize) return;
  if (lastLineWidth(t) + px('space/2') + room.width <= t.width) setProps(b, { 'Room for the time': false });
}
const initialsOf = (name) => name.split(' ').slice(0, 2).map((w) => w[0]).join('');
/** Gives the message instance [b] the content of [m]; first: it opens a run. */
function dress(b, m, device, first) {
  if (m.time) setProps(b, { Time: m.time });
  if (m.text) setProps(b, { Text: m.text });
  if (m.ticks) b.findOne((n) => n.name === 'ticks').setProperties({ State: m.ticks });
  if (m.attach) {
    const [set, props, values, name] = m.attach;
    // A text under an attachment is its caption. With no text the time sits in the last line of a file or a voice message; a picture keeps a line for it.
    setProps(b, { Attachment: true, Caption: !!m.text, 'Show text': !!m.text, 'Text line': !m.text && set === 'Media card' });
    const a = b.findOne((n) => n.name === 'attachment');
    a.swapComponent(variant(set, { ...props, Tone: m.kind === 'out' ? 'Outgoing' : 'Surface', Device: device }));
    setProps(a, values);
    if (name) nameFile(a, name);
  }
  if (m.text) seatTime(b, !!m.attach);
  if (!m.from) return;
  setProps(b, { Gutter: true, Avatar: first, Sender: first && !m.state });
  if (!first) return;
  if (!m.state) setProps(b, { 'Sender name': m.from, Fingerprint: m.print });
  dressAvatar(b, { Plate: m.plate ?? '1', Size: 'Compact' }, { Initials: initialsOf(m.from) });
}
/** A feed of [items] at the width of a conversation on [device]. */
function thread(name, device, items) {
  const t = surface(`${name} · ${device}`, 'background', { dir: 'V', gap: 1, pad: [4, feedPad(device)], w: FEED[device], align: 'MIN' });
  const run = (a, b) => a && a.kind === b.kind && a.from === b.from && (a.kind === 'in' || a.kind === 'out');
  items.forEach((m, i) => {
    if (m.kind === 'date') return add(t, setProps(inst('Date divider'), { Date: m.date }), { fillW: true });
    if (m.kind === 'unread') return add(t, inst('Unread divider'), { fillW: true });
    if (m.kind === 'notice') return add(t, setProps(inst('Group notice'), { Notice: m.notice }), { fillW: true });
    const first = !run(items[i - 1], m), last = !run(items[i + 1], m);
    const row = add(t, box('row', { dir: 'H', justify: m.kind === 'out' || m.direction === 'Outgoing' ? 'MAX' : 'MIN', pad: first && i ? [2, 0, 0, 0] : 0 }), { fillW: true });
    if (m.kind === 'call') return add(row, setProps(inst('Call log entry', { Direction: m.direction }), { Detail: m.detail }));
    const Position = first && last ? 'Single' : first ? 'First' : last ? 'Last' : 'Middle';
    const b = add(row, inst(m.kind === 'out' ? 'Outgoing message' : 'Incoming message', { Position, Device: device, State: m.state ?? 'Default' }));
    dress(b, m, device, first);
  });
  return t;
}
for (const [label, items] of [['Direct chat', DM], ['Group', GROUP], ['Files, pictures and voice', FILES], ['Long link, token and name', HARD]]) {
  await examples(label, [thread(label, 'Desktop', items), thread(label, 'Phone', items)], 'MIN');
}
