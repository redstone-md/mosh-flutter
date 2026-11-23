// Threads assembled from the message and feed components, to judge the
// density of the feed and the rhythm of its runs on real conversations: the
// captured "Conversation / DM / Thread" and "Conversation / Group / Thread",
// then a feed of attachments and one of text that is hard to wrap.
card('Thread', 'The components in use. Bubbles of one run sit 4 px apart and a new run starts 12 px lower. The last example holds what a feed has to survive: a long link, a token without spaces and a long name.');
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
for (const [label, items] of [['Direct chat', DM], ['Group', GROUP], ['Files, pictures and voice', FILES], ['Long link, token and name', HARD]]) {
  await examples(label, [thread(label, 'Desktop', items), thread(label, 'Phone', items)], 'MIN');
}
