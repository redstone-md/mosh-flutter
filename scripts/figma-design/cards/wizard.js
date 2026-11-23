// Steps of a flow: first-run setup (SetupFrame, SetupHeading, SetupProgress),
// a step of the start menu (StartStep) and the steps of linking a device
// (device_link_steps._Step).
card('Wizard step', 'A step asks for one thing. Its heading is the question, the line under it says why Mosh asks, and one primary button moves on; Back is always the quiet one under it. Setup is a real sequence of three, so it counts its steps: done ones are ticked, the current one is filled. Linking a device counts the same way inside its card. A step opened from the start menu has no count, only the way back.');
const STEP_W = { Desktop: 480, Phone: ROW.Phone };
/** The numbered mark of a step. key: its size as a space key. */
function mark(n, State, key) {
  const done = State === 'Done', now = State === 'Current';
  const m = box('mark', { dir: 'H', wk: key, hk: key, r: 'full', justify: 'CENTER', fill: now ? 'primary' : done ? 'secondaryContainer' : null, stroke: now || done ? null : 'outline' });
  add(m, done ? icon('check', 'onSecondaryContainer', 4) : text(String(n), 'labelLarge', now ? 'onPrimary' : 'onSurfaceMuted', { name: 'number' }));
  return m;
}
const stateOf = (i, at) => (i < at ? 'Done' : i === at ? 'Current' : 'Upcoming');
const SETUP = ['Name', 'Device', 'Network'];
display(await grid('Setup progress', axis('Step', ['1', '2', '3']), DEVICES, ({ Step, Device }) => {
  const p = box('Setup progress', { component: true, dir: 'H', gap: 2, w: Device === 'Desktop' ? 360 : DIALOG.Phone, align: 'MIN' });
  SETUP.forEach((label, i) => {
    const State = stateOf(i, Step - 1);
    if (i) {
      const line = add(add(p, box('line', { dir: 'H', hk: 8 }), { fillW: true }), rect('line', { fill: State === 'Upcoming' ? 'outlineVariant' : 'primary' }), { fillW: true });
      bind(line, 'height', 'border/thick');
    }
    const s = add(p, box(label, { dir: 'V', gap: 1 }));
    add(s, mark(i + 1, State, 8));
    add(s, text(label, 'labelMedium', State === 'Upcoming' ? 'onSurfaceMuted' : 'onSurface'));
  });
  return p;
}));
const links = display(await grid('Link step', ONE, axis('State', ['Done', 'Current', 'Upcoming']), ({ State }) => {
  const s = box('Link step', { component: true, dir: 'H', gap: 2 });
  add(s, mark(1, State, 6));
  add(s, text('Read QR', 'labelMedium', State === 'Upcoming' ? 'onSurfaceMuted' : 'onSurface', { name: 'label' }));
  return s;
}));
prop(links, 'Label', 'TEXT', 'Read QR', 'label');
prop(links, 'Number', 'TEXT', '1', 'number');
/** The three steps of linking a device, [at] the current one. */
function linkSteps(parent, at) {
  const r = add(parent, box('link steps', { dir: 'H', gap: 4 }), { fillW: true });
  r.layoutWrap = 'WRAP'; space(r, 'counterAxisSpacing', 2);
  ['Read QR', 'Confirm code', 'Link devices'].forEach((Label, i) => add(r, setProps(inst('Link step', { State: stateOf(i, at) }), { Label, Number: String(i + 1) })));
}
/** The question a step asks and why Mosh asks it. */
function question(parent, title, lead, centred) {
  const h = add(parent, box('question', { dir: 'V', gap: 2, align: centred ? 'CENTER' : 'MIN' }), { fillW: true });
  titled(h, [title, 'headlineMedium', 'onSurface'], [lead, 'bodyLarge', 'onSurfaceVariant'], centred);
}
const field = (Device, values = {}) => setProps(inst('Text field', { State: 'Default', Device }), values);
// Per kind: what the step holds, top to bottom.
const STEPS = {
  'Setup name': (s, Device) => {
    add(s, inst('Setup progress', { Step: '1', Device }));
    question(s, 'What should people call you?', 'Your name is shown to the people you talk to. You can change it later.');
    add(s, field(Device), { fillW: true });
    add(s, inst('Inline note', { Kind: 'Privacy', Device }), { fillW: true });
    add(s, labelButton(Device, 'Continue'), { fillW: true });
  },
  'Setup device': (s, Device) => {
    add(s, inst('Setup progress', { Step: '2', Device }));
    question(s, 'Set up this device', 'Start here if this is your first device, or connect it to the Mosh you already use.');
    const c = add(s, cardSurface('link card', { dir: 'V', gap: 4, pad: cardPad(Device), align: 'MIN' }), { fillW: true });
    header(c, 'qr', 'Connect this device', 'On the device you already use, open Settings, Devices, Link another device. Read its QR here, then show it your confirmation code.');
    linkSteps(c, 0);
    add(c, labelButton(Device, 'Choose QR image', { Kind: 'Outlined', glyph: 'image' }), { fillW: true });
    add(c, field(Device, { Label: 'Link from your trusted device', Placeholder: 'mosh://device-link/…' }), { fillW: true });
    add(s, labelButton(Device, 'This is my first device'), { fillW: true });
    add(s, labelButton(Device, 'Back', { Kind: 'Text' }));
  },
  'Start menu step': (s, Device) => {
    add(add(s, box('back', { dir: 'H' }), { fillW: true }), textButton(Device, 'Back', 'back'));
    question(s, 'Join a public channel', 'Join an open room by its name', true);
    const c = add(s, cardSurface('channel card', { dir: 'V', gap: 4, pad: cardPad(Device) }), { fillW: true });
    add(c, inst('Inline note', { Kind: 'Open channel', Device }), { fillW: true });
    add(c, field(Device, { Label: 'Channel name', Placeholder: 'Latin letters, digits, - and _', Icon: true, 'Icon glyph': glyphOf('tag') }), { fillW: true });
    add(c, labelButton(Device, 'Join channel', { State: 'Disabled' }), { fillW: true });
    const tips = add(c, box('examples', { dir: 'H', gap: 2 }));
    add(tips, text('For example', 'labelMedium', 'onSurfaceMuted'));
    ['news', 'dev', 'community'].forEach((Label) => add(tips, setProps(inst('Suggestion chip', { State: 'Default', Device }), { Label: '#' + Label })));
  },
  'Link a device': (s, Device) => {
    const c = add(s, cardSurface('link card', { dir: 'V', gap: 4, pad: cardPad(Device), align: 'MIN' }), { fillW: true });
    header(c, 'devices', 'Link another device', 'Check that the other device shows the same code, then confirm there');
    linkSteps(c, 1);
    const code = add(c, inset('code', { dir: 'V', gap: 1, pad: [4, 0] }), { fillW: true });
    add(code, text('Confirmation code', 'labelMedium', 'onSurfaceVariant'));
    add(code, text('482 913', 'displaySmall', 'onSurface', { name: 'confirmation code' }));
    add(c, labelButton(Device, 'Cancel', { Kind: 'Text' }));
  },
};
display(await grid('Wizard step', axis('Kind', Object.keys(STEPS)), DEVICES, ({ Kind, Device }) => {
  const s = surface('Wizard step', 'background', { component: true, dir: 'V', gap: 5, pad: Device === 'Phone' ? 4 : 6, w: STEP_W[Device] + px('space/' + (Device === 'Phone' ? 4 : 6)) * 2 });
  STEPS[Kind](s, Device);
  return s;
}));
