// Icon button: IconButton, the attachment actions and the viewer's close button.
card('Icon button', 'An action that an icon alone can name; it always has a tooltip. Standard sits on a surface. Tonal has its own plate, for actions on top of media and file cards: download, retry, cancel, close. Desktop is 40 px, phone 48 px.');
function iconButton({ Kind, State, Device }) {
  const off = State === 'Disabled', phone = Device === 'Phone', tonal = Kind === 'Tonal';
  const ink = tonal || off ? 'onSurface' : 'onSurfaceVariant';
  const b = box('Icon button', { component: true, dir: 'H', wk: phone ? 12 : 10, hk: phone ? 12 : 10, r: 'full', clip: true, justify: 'CENTER', fill: tonal && !off ? 'surfaceContainerHighest' : null });
  const glyph = add(b, icon('close', ink, phone ? 6 : 5));
  if (off) disable(b, [glyph], tonal);
  interact(b, State, 'onSurface');
  return b;
}
const set = await grid('Icon button', perDevice(axis('Kind', ['Standard', 'Tonal'])), STATES5, iconButton);
prop(set, 'Icon glyph', 'INSTANCE_SWAP', ICONS.close, 'icon');
await examples('Attachment actions and viewer close', ['download', 'refresh', 'close'].map((g) => setProps(inst('Icon button', { Kind: 'Tonal', State: 'Default', Device: 'Desktop' }), { 'Icon glyph': ICONS[g] })));
