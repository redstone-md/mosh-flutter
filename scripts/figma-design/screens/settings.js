// Settings, Sound and video: "Settings / Sound & Video / Default" of the capture.
// Per card: glyph, what it is about, the line under it and the label of its list.
const USED = [['mic', 'Microphone', 'Used for calls and voice messages', 'Input device'], ['video', 'Camera', 'Used for video calls', 'Video device'], ['speaker', 'Speakers', 'Where calls and ringtones play', 'Output device']];
/** The section's page in [parent]: its header, a card per device and the test of the sound. */
function page(parent, Device) {
  const phone = Device === 'Phone', wide = phone ? { fillW: true } : {};
  const col = stretch(parent, 'page', { dir: 'V', gap: 6, pad: phone ? [1, 4, 4, 4] : [8, 10] });
  add(col, inst('Page header', { Device }), wide);
  const cards = add(col, box('cards', { dir: 'V', gap: 3, align: 'MIN' }), wide);
  for (const [glyph, Subject, About, Label] of USED) {
    const c = add(cards, setProps(inst('Settings card', { Kind: 'Control', Device }), { Subject, About, 'Subject glyph': glyphOf(glyph) }), wide);
    setProps(c.findOne((n) => n.type === 'INSTANCE' && n.name === 'Select'), { Label, Value: 'System default' });
  }
  add(col, labelButton(Device, 'Play test sound', { Kind: 'Outlined', glyph: 'speaker' }));
}
const row = stretch(screen('Settings, sound and video', 'Desktop'), 'panels');
add(row, inst('Settings navigation', { Device: 'Desktop' }), { fillH: true });
page(row, 'Desktop');
page(screen('Settings, sound and video', 'Phone'), 'Phone');
