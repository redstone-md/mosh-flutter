// Text field: TextField, InlineError and the read-only invite link field.
card('Text field', 'A recessed well with a visible edge. The label sits above and stays while the user types. An error turns the edge red and says what to fix on the line below. The read-only field holds a link and its copy action.');
const error = await grid('Inline error', ONE, ONE, () => {
  const e = box('Inline error', { component: true, dir: 'H', gap: 1 });
  add(e, icon('error', 'error', 4));
  add(e, text('Enter a name', 'bodySmall', 'error', { name: 'message' }));
  return e;
});
prop(error, 'Message', 'TEXT', 'Enter a name', 'message');

const STATES = axis('State', ['Default', 'Hover', 'Focus', 'Filled', 'Error', 'Disabled', 'Read-only']);
function field({ State, Device }) {
  const off = State === 'Disabled', ro = State === 'Read-only';
  const f = box('Text field', { component: true, gap: 2, w: 280, align: 'MIN' });
  const label = add(f, text(ro ? 'Invite link' : 'Display name', 'labelMedium', 'onSurfaceVariant', { name: ro ? 'link label' : 'label' }));
  const edge = State === 'Focus' ? 'primary' : State === 'Error' ? 'error' : off || ro ? 'outlineVariant' : 'outline';
  const field = well(f, { device: Device, edge, thick: State === 'Focus', off, pad: [0, ro ? 0 : 4, 0, 4] });
  const lead = add(field, icon('person', 'onSurfaceVariant'));
  lead.name = 'leading icon';
  if (State === 'Focus') bind(add(field, rect('caret', { fill: 'primary', hk: 5 })), 'width', 'border/thick');
  const empty = ['Default', 'Hover', 'Focus'].includes(State);
  const value = add(field, text(ro ? 'mosh.link/i/7x9k-a2p8-drift' : empty ? 'Your display name' : 'Maya Chen', 'bodyMedium', empty ? 'onSurfaceMuted' : 'onSurface', { name: ro ? 'link' : empty ? 'placeholder' : 'value', truncate: true }), { fillW: true });
  if (ro) add(field, setProps(inst('Icon button', { Kind: 'Standard', State: 'Default', Device }), { 'Icon glyph': ICONS.copy }));
  if (off) disable(f, [label, value, lead]);
  if (State === 'Hover') tint(field, 'onSurface', 'hover');
  if (State === 'Error') add(f, inst('Inline error'));
  return f;
}
const set = await grid('Text field', perDevice(), STATES, field);
prop(set, 'Label', 'TEXT', 'Display name', 'label');
prop(set, 'Show label', 'BOOLEAN', true, 'label');
prop(set, 'Placeholder', 'TEXT', 'Your display name', 'placeholder');
prop(set, 'Value', 'TEXT', 'Maya Chen', 'value');
prop(set, 'Icon', 'BOOLEAN', false, 'leading icon');
prop(set, 'Icon glyph', 'INSTANCE_SWAP', ICONS.person, 'leading icon');
prop(set, 'Link label', 'TEXT', 'Invite link', 'link label');
prop(set, 'Link', 'TEXT', 'mosh.link/i/7x9k-a2p8-drift', 'link');
