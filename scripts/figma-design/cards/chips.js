// Chips and segments: ChoiceChip (chat list filters), ActionChip (examples), the search filter segment.
card('Chip and segment', 'A filter chip narrows a list and stays lit while it applies. A suggestion chip fills in an example with one tap. Segments switch what a search looks through, and exactly one is always on. All are 32 px tall, inside a 48 px tap target on the phone.');
const SELECTED = [['Selected', { Selected: 'Yes' }], ['Not selected', { Selected: 'No' }]];
function filter({ Selected, State, Device }) {
  const on = Selected === 'Yes', off = State === 'Disabled';
  const ink = off ? 'onSurface' : on ? 'onSecondaryContainer' : 'onSurfaceVariant';
  const chip = box('chip', { dir: 'H', gap: 1, pad: [0, 3], hk: 8, r: 'full', clip: true, fill: on && !off ? 'secondaryContainer' : null, stroke: on || State === 'Focus' ? null : 'outlineVariant' });
  const lead = add(chip, icon('group', ink, 4)); lead.name = 'leading icon';
  const label = add(chip, text('Groups', 'labelLarge', ink, { name: 'label' }));
  if (off) disable(chip, [lead, label], on);
  interact(chip, State, ink);
  return shell('Filter chip', chip, Device);
}
const filters = await grid('Filter chip', perDevice(SELECTED), STATES5, filter);
prop(filters, 'Label', 'TEXT', 'Groups', 'label');
prop(filters, 'Icon', 'BOOLEAN', false, 'leading icon');
prop(filters, 'Icon glyph', 'INSTANCE_SWAP', ICONS.group, 'leading icon');

function suggestion({ State, Device }) {
  const off = State === 'Disabled';
  const chip = box('chip', { dir: 'H', pad: [0, 3], hk: 8, r: 'full', clip: true, fill: off ? null : 'surfaceContainerHigh' });
  const label = add(chip, text('#photography', 'labelLarge', 'onSurface', { name: 'label' }));
  if (off) disable(chip, [label], true);
  interact(chip, State, 'onSurface');
  return shell('Suggestion chip', chip, Device);
}
const suggestions = await grid('Suggestion chip', perDevice(), STATES5, suggestion);
prop(suggestions, 'Label', 'TEXT', '#photography', 'label');

function segment({ Selected, State, Device }) {
  const on = Selected === 'Yes', ink = on ? 'onSurface' : 'onSurfaceVariant';
  const seg = box('segment', { dir: 'H', gap: 1, pad: [0, 3], hk: 8, r: 'full', clip: true, fill: on ? 'surfaceBright' : null });
  const lead = add(seg, icon('attach', ink, 4)); lead.name = 'leading icon';
  add(seg, text('Files', 'labelLarge', ink, { name: 'label' }));
  interact(seg, State, 'onSurface');
  return shell('Segment', seg, Device);
}
const segments = await grid('Segment', perDevice(SELECTED), axis('State', ['Default', 'Hover', 'Pressed', 'Focus']), segment);
prop(segments, 'Label', 'TEXT', 'Files', 'label');
prop(segments, 'Icon', 'BOOLEAN', false, 'leading icon');
prop(segments, 'Icon glyph', 'INSTANCE_SWAP', ICONS.attach, 'leading icon');

const chipRow = ['All', 'Personal', 'Groups', 'Channels'].map((l, i) => setProps(inst('Filter chip', { Selected: i ? 'No' : 'Yes', State: 'Default', Device: 'Desktop' }), { Label: l }));
await examples('Chat list filters', chipRow);
const control = box('Segmented control', { dir: 'H', pad: 1, gap: 1, r: 'full', fill: 'surfaceContainerLowest' });
add(control, setProps(inst('Segment', { Selected: 'Yes', State: 'Default', Device: 'Desktop' }), { Label: 'All' }));
add(control, setProps(inst('Segment', { Selected: 'No', State: 'Default', Device: 'Desktop' }), { Label: 'Files', Icon: true }));
await examples('Search filter', [control]);
