// Switch and the settings row that carries one (SettingsToggleCard).
card('Switch', 'A setting that takes effect at once. On is the saffron track. The row names the setting, explains it in one line and shows a spinner while the change is being saved. The whole row is the press target; a switch on its own gets a 48 px one on the phone.');
function toggle({ Value, State, Device }) {
  const on = Value === 'On', off = State === 'Disabled';
  const track = box('track', { dir: 'H', wk: 10, hk: 6, pad: [0, 1], r: 'full', clip: true, justify: on ? 'MAX' : 'MIN',
    fill: off ? null : on ? 'primary' : 'surfaceContainerHighest', stroke: on || State === 'Focus' ? null : off ? 'outlineVariant' : 'outline' });
  const thumb = add(track, dot('thumb', off ? 'onSurface' : on ? 'onPrimary' : 'outline', 4));
  if (off) disable(track, [thumb], on);
  interact(track, State, on ? 'onPrimary' : 'onSurface');
  return shell('Switch', track, Device);
}
const VALUES = perDevice(axis('Value', ['On', 'Off']));
await grid('Switch', VALUES, STATES5, toggle);

function tile({ Value, State, Device }) {
  const off = State === 'Disabled' || State === 'Saving';
  const t = box('Switch row', { component: true, dir: 'H', gap: 4, pad: [3, 3], r: 'medium', clip: true, w: Device === 'Phone' ? 358 : 420, minHk: 12 });
  const words = add(t, box('text', { gap: 1, align: 'MIN' }), { fillW: true });
  const title = add(words, text('Read receipts', 'titleSmall', 'onSurface', { name: 'title' }), { fillW: true });
  const sub = add(words, text('Let contacts see when you have read their messages', 'bodySmall', 'onSurfaceVariant', { name: 'subtitle', w: 240 }), { fillW: true });
  if (State === 'Disabled') disable(t, [title, sub]);
  if (State === 'Saving') add(t, spinner('onSurfaceVariant'));
  add(t, inst('Switch', { Value, State: off ? 'Disabled' : 'Default', Device }));
  interact(t, State, 'onSurface');
  return t;
}
const tiles = await grid('Switch row', VALUES, axis('State', ['Default', 'Hover', 'Pressed', 'Focus', 'Disabled', 'Saving']), tile);
prop(tiles, 'Title', 'TEXT', 'Read receipts', 'title');
prop(tiles, 'Subtitle', 'TEXT', 'Let contacts see when you have read their messages', 'subtitle');
