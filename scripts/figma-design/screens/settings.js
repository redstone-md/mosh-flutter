// Settings, Sound and video: "Settings / Sound & Video / Default" of the capture.
// Per card: glyph, what it is about, the line under it and the label of its list.
const USED = [['mic', 'Microphone', 'Used for calls and voice messages', 'Input device'], ['video', 'Camera', 'Used for video calls', 'Video device'], ['speaker', 'Speakers', 'Where calls and ringtones play', 'Output device']];
// The section's page: its header, a card per device and the test of the sound.
for (const Device of ['Desktop', 'Phone']) {
  const col = settingsPage('Settings, sound and video', Device), wide = pageWide(Device);
  add(col, inst('Page header', { Device }), wide);
  const cards = add(col, box('cards', { dir: 'V', gap: 3, align: 'MIN' }), wide);
  for (const [glyph, Subject, About, Label] of USED) {
    const c = add(cards, setProps(inst('Settings card', { Kind: 'Control', Device }), { Subject, About, 'Subject glyph': glyphOf(glyph) }), wide);
    setProps(c.findOne((n) => n.type === 'INSTANCE' && n.name === 'Select'), { Label, Value: 'System default' });
  }
  add(col, labelButton(Device, 'Play test sound', { Kind: 'Outlined', glyph: 'speaker' }));
}
