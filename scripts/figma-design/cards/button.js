// Button: FilledButton, OutlinedButton, TextButton and FieldLogButton (a text button with an icon).
const STATES = axis('State', ['Default', 'Hover', 'Pressed', 'Focus', 'Disabled', 'Loading']);
card('Button', 'One action per pill. Primary carries the main action of a screen, outlined a second choice, text the quiet ones. Desktop is 40 px tall, phone 48 px. Loading keeps the label and blocks the press.');

function button({ Kind, State, Device }) {
  const off = State === 'Disabled';
  const ink = off ? 'onSurface' : Kind === 'Primary' ? 'onPrimary' : 'primary';
  const b = box('Button', {
    component: true, dir: 'H', gap: 2, pad: [0, Kind === 'Text' ? 4 : 6], hk: controlHeight(Device), minWk: Device === 'Phone' ? 12 : null, r: 'full', clip: true, justify: 'CENTER',
    fill: Kind === 'Primary' && !off ? 'primary' : null,
    stroke: Kind === 'Outlined' && State !== 'Focus' ? (off ? 'outlineVariant' : 'outline') : null,
  });
  const lead = add(b, State === 'Loading' ? spinner(ink) : icon('add', ink));
  lead.name = State === 'Loading' ? 'spinner' : 'leading icon';
  const label = add(b, text('Continue', 'labelLarge', ink, { name: 'label' }));
  if (off) disable(b, [lead, label], Kind === 'Primary');
  interact(b, State, ink);
  return b;
}
const set = await grid('Button', perDevice(axis('Kind', ['Primary', 'Outlined', 'Text'])), STATES, button);
prop(set, 'Label', 'TEXT', 'Continue', 'label');
prop(set, 'Icon', 'BOOLEAN', false, 'leading icon');
prop(set, 'Icon glyph', 'INSTANCE_SWAP', ICONS.add, 'leading icon');
