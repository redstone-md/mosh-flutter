// Progress: CircularProgressIndicator, LinearProgressIndicator and MoshProgressBar.
card('Progress', 'A spinner when the wait has no measure, a bar when it does. The transfer bar adds what a file transfer can tell: how much has gone through. The indeterminate shapes are a still frame of the animation.');
// Diameter as a space key and ring width over the radius: 2, 2 and 4 px.
const RING = { Small: [4, 0.25], Medium: [6, 1 / 6], Large: [10, 0.2] };
await grid('Circular progress', ONE, axis('Size', Object.keys(RING)), ({ Size }) => {
  const [key, thick] = RING[Size];
  const p = box('Circular progress', { component: true, dir: 'H' });
  add(p, spinner('primary', key, thick));
  return p;
});
function bar(name, determinate, component) {
  const track = box(name, { component, dir: 'H', w: 240, hk: 1, r: 'full', clip: true, fill: 'surfaceContainerHighest', justify: determinate ? 'MIN' : 'CENTER' });
  add(track, rect('indicator', { fill: 'primary', w: determinate ? 144 : 96, hk: 1, r: 'full' }));
  return track;
}
await grid('Linear progress', ONE, axis('Kind', ['Determinate', 'Indeterminate']), ({ Kind }) => bar('Linear progress', Kind === 'Determinate', true));
const transfer = await grid('Transfer bar', ONE, axis('Kind', ['Determinate', 'Indeterminate']), ({ Kind }) => {
  const measured = Kind === 'Determinate';
  const t = box('Transfer bar', { component: true, gap: 2, w: 240, align: 'MIN' });
  add(t, bar('bar', measured, false), { fillW: true });
  const line = add(t, box('caption', { dir: 'H', gap: 2 }), { fillW: true });
  add(line, text(measured ? '4.9 of 8.1 MB' : 'Waiting for Maya', 'bodySmall', 'onSurfaceVariant', { name: measured ? 'amount' : 'status' }), { fillW: true });
  if (measured) add(line, text('60%', 'bodySmall', 'onSurfaceVariant', { name: 'percent' }));
  return t;
});
prop(transfer, 'Amount', 'TEXT', '4.9 of 8.1 MB', 'amount');
prop(transfer, 'Percent', 'TEXT', '60%', 'percent');
prop(transfer, 'Status', 'TEXT', 'Waiting for Maya', 'status');
