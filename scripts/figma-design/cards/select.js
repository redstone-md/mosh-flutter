// Select: MoshSelect and AudioDevicePicker. A popover menu on the desktop, a bottom sheet on the phone.
card('Select', 'One choice out of a short list. The closed control reads like a text field with a caret. On the desktop it opens a menu under itself, on the phone a sheet from the bottom edge. When the list cannot load, the control says so and offers a retry.');
function option({ State, Device }) {
  const on = State === 'Selected', off = State === 'Disabled';
  const o = box('Select option', { component: true, dir: 'H', gap: 3, pad: [0, 3], hk: controlHeight(Device), w: 264, r: 'small', clip: true, fill: on ? 'secondaryContainer' : null });
  const label = add(o, text('USB Microphone', 'bodyMedium', on ? 'onSecondaryContainer' : 'onSurface', { name: 'label', truncate: true }), { fillW: true });
  if (on) add(o, icon('check', 'onSecondaryContainer'));
  if (off) disable(o, [label]);
  interact(o, State, 'onSurface');
  return o;
}
const optionSet = await grid('Select option', perDevice(), axis('State', ['Default', 'Hover', 'Pressed', 'Focus', 'Selected', 'Disabled']), option);
prop(optionSet, 'Label', 'TEXT', 'USB Microphone', 'label');

const STATES = axis('State', ['Closed', 'Hover', 'Focus', 'Open', 'Disabled', 'Error']);
function select({ State, Device }) {
  const off = State === 'Disabled', open = State === 'Open', failed = State === 'Error';
  const s = box('Select', { component: true, gap: 2, w: 280, align: 'MIN' });
  const label = add(s, text('Microphone', 'labelMedium', 'onSurfaceVariant', { name: 'label' }));
  const edge = open ? 'primary' : failed ? 'error' : off ? 'outlineVariant' : 'outline';
  const field = well(s, { device: Device, edge, thick: open, off, pad: [0, 3, 0, 4] });
  const value = add(field, text(failed ? 'No devices' : off ? 'Loading devices…' : 'USB Microphone', 'bodyMedium', failed ? 'onSurfaceMuted' : 'onSurface', { name: failed ? 'empty value' : off ? 'pending value' : 'value', truncate: true }), { fillW: true });
  const caret = add(field, icon('expand_more', 'onSurfaceVariant'));
  if (open) caret.rotation = 180;
  if (off) disable(s, [label, value, caret]);
  interact(field, State, 'onSurface');
  if (failed) {
    const line = add(s, box('error line', { dir: 'H', gap: 2 }), { fillW: true });
    add(line, setProps(inst('Inline error'), { Message: 'Could not load devices' }), { fillW: true });
    add(line, setProps(inst('Button', { Kind: 'Text', State: 'Default', Device }), { Label: 'Retry' }));
  }
  return s;
}
const set = await grid('Select', perDevice(), STATES, select);
prop(set, 'Label', 'TEXT', 'Microphone', 'label');
prop(set, 'Value', 'TEXT', 'USB Microphone', 'value');

const OPTIONS = [['System default', 'Default'], ['USB Microphone', 'Selected'], ['Built-in Microphone', 'Default']];
const options = (parent, Device) => OPTIONS.forEach(([label, State]) => add(parent, setProps(inst('Select option', { State, Device }), { Label: label }), { fillW: true }));
await grid('Select menu', ONE, [['Desktop', {}]], () => {
  const m = box('Select menu', { component: true, pad: 2, gap: 1, w: 280, r: 'large', fill: 'surfaceContainerHigh', stroke: 'outlineVariant', effect: 'elevation2' });
  options(m, 'Desktop');
  return m;
});
await grid('Select sheet', ONE, [['Phone', {}]], () => {
  const frame = box('Select sheet', { component: true, w: 390, h: 420, justify: 'MAX', clip: true, fill: 'surface' });
  tint(frame, 'surfaceContainerLowest', 'scrim').name = 'scrim';
  const sheet = add(frame, box('sheet', { pad: [3, 3, 6, 3], gap: 2, fill: 'surfaceContainerHigh', effect: 'elevation3' }), { fillW: true });
  ['topLeftRadius', 'topRightRadius'].forEach((f) => bind(sheet, f, 'radius/extraLarge'));
  add(sheet, rect('handle', { fill: 'outline', wk: 8, hk: 1, r: 'full' }));
  const head = add(sheet, box('title', { dir: 'H', pad: [0, 0, 0, 3] }), { fillW: true });
  add(head, text('Microphone', 'titleMedium', 'onSurface', { name: 'sheet title' }), { fillW: true });
  add(head, inst('Icon button', { Kind: 'Standard', State: 'Default', Device: 'Phone' }));
  options(sheet, 'Phone');
  return frame;
});
