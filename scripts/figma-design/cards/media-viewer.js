// The full-screen viewer of an attachment: MediaViewer with its caption, the
// image stage, the audio card with its playback controls and time label, and
// the placeholder for what cannot be shown.
card('Media viewer', 'The viewer takes the whole window and the lowest, darkest tone, so nothing competes with the picture. The file’s name and who sent it sit in a bar at the top with the two things to do: save it and close. A sound gets a player. What Mosh cannot show says so and offers to save the file instead of leaving an empty stage.');
const VIEW = { Desktop: [720, 460], Phone: [390, 640] };
/** A message in place of the media, with the way out. */
function placeholder(stage, Device, glyph, title, line) {
  const col = add(stage, box('placeholder', { dir: 'V', gap: 2, w: 300 }));
  add(col, icon(glyph, 'onSurfaceVariant', 10));
  for (const t of [para(col, title, 'titleMedium', 'onSurface', 'title'), para(col, line, 'bodyMedium', 'onSurfaceVariant', 'line')]) t.textAlignHorizontal = 'CENTER';
  add(add(col, box('action', { dir: 'H', pad: [2, 0, 0, 0] })), button(Device, 'Save as…', { Kind: 'Outlined', glyph: 'download' }));
}
// Per kind: the file's name and what the stage shows.
const MEDIA = {
  Image: ['harbour.jpg', (stage) => {
    // The plate stands for the picture itself, which a screen puts in its place.
    const view = add(stage, box('picture', { dir: 'H', r: 'medium', fill: 'tertiaryContainer', justify: 'CENTER' }), { fillW: true, fillH: true });
    add(view, icon('image', 'onTertiaryContainer', 12));
  }],
  Audio: ['harbour-ambience.mp3', (stage, Device) => {
    const player = add(stage, surface('player', 'popup', { dir: 'H', gap: 2, pad: [3, 5, 3, 3], r: 'extraLarge' }), { fillW: true });
    add(player, action('pause', Device, { Kind: 'Tonal' }));
    // The slider's track is as long as the player leaves room for.
    add(player, inst('Slider', { State: 'Default', Device }), { fillW: true }).findOne((n) => n.name === 'slider').layoutSizingHorizontal = 'FILL';
    add(player, text('1:12 / 3:24', 'labelMedium', 'onSurfaceVariant', { name: 'time' }));
  }],
  'Video unavailable': ['waves.mp4', (stage, Device) => placeholder(stage, Device, 'video', 'This video cannot be played here', 'Save it to watch it in another app')],
  'Unsupported file': ['coast-route.gpx', (stage, Device) => placeholder(stage, Device, 'file', 'No preview for this file', 'Save it to open it in another app')],
};
display(await grid('Media viewer', axis('Kind', Object.keys(MEDIA)), DEVICES, ({ Kind, Device }) => {
  const [name, show] = MEDIA[Kind], [w, h] = VIEW[Device];
  const v = box('Media viewer', { component: true, dir: 'V', w, h, fill: 'surfaceContainerLowest', clip: true });
  const bar = add(v, box('bar', { dir: 'H', gap: 2, pad: [2, 2, 2, 5] }), { fillW: true });
  const col = add(bar, box('file', { dir: 'V', align: 'MIN' }), { fillW: true });
  add(col, text(name, 'titleSmall', 'onSurface', { name: 'name', truncate: true }), { fillW: true });
  add(col, text('Maya Chen, Nov 21 at 9:38 AM', 'bodySmall', 'onSurfaceVariant', { name: 'sent', truncate: true }), { fillW: true });
  add(bar, action('download', Device)).name = 'save';
  add(bar, action('close', Device)).name = 'close';
  const stage = add(v, box('stage', { dir: 'V', pad: [0, Device === 'Phone' ? 3 : 6, Device === 'Phone' ? 6 : 6, Device === 'Phone' ? 3 : 6], justify: 'CENTER' }), { fillW: true, fillH: true });
  show(stage, Device);
  return v;
}));
