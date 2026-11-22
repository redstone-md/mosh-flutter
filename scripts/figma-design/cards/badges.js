// Badges: UnreadBadge, StatePill (title bar) and the diagnostics status badge.
card('Badge and status pill', 'The unread badge counts and stops at 99+. The state pill in the title bar tells whether Mosh is connected, and shrinks to its dot in a narrow window. The status badge grades a diagnostics summary; the word carries the meaning, the colour repeats it.');
const unread = await grid('Unread badge', ONE, ONE, () => {
  const b = box('Unread badge', { component: true, dir: 'H', pad: [0, 1], hk: 5, minWk: 5, r: 'full', fill: 'primary', justify: 'CENTER' });
  add(b, text('2', 'labelMedium', 'onPrimary', { name: 'count' }));
  return b;
});
prop(unread, 'Count', 'TEXT', '2', 'count');
await examples('One digit, two digits, over 99', ['2', '14', '99+'].map((n) => setProps(inst('Unread badge'), { Count: n })));

const PILL = { Ready: ['success', 'Connected'], Waiting: ['warning', 'Connecting'], 'No data': ['outline', 'Offline'] };
await grid('State pill', axis('Size', ['Full', 'Compact']), axis('State', Object.keys(PILL)), ({ Size, State }) => {
  const full = Size === 'Full';
  const p = box('State pill', { component: true, dir: 'H', gap: 2, pad: full ? [0, 3] : 0, hk: 6, wk: full ? null : 6, r: 'full', stroke: 'outlineVariant', justify: 'CENTER' });
  add(p, dot('dot', PILL[State][0], 2));
  if (full) add(p, text(PILL[State][1], 'labelMedium', 'onSurfaceVariant', { name: 'label' }));
  return p;
});

const TONE = { Ok: ['success', 'surfaceContainerHighest', 'onSurface', 'Healthy'], Warning: ['warning', 'warningContainer', 'onWarningContainer', 'Degraded'], Error: ['error', 'errorContainer', 'onErrorContainer', 'Failed'] };
await grid('Status badge', ONE, axis('Tone', Object.keys(TONE)), ({ Tone }) => {
  const [mark, plate, ink, word] = TONE[Tone];
  const b = box('Status badge', { component: true, dir: 'H', gap: 2, pad: [0, 3, 0, 2], hk: 6, r: 'full', fill: plate });
  add(b, dot('dot', mark, 2));
  add(b, text(word, 'labelMedium', ink, { name: 'label' }));
  return b;
});
