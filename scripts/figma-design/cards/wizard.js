// Steps of a flow: first-run setup (SetupFrame, SetupHeading, SetupProgress),
// a step of the start menu (StartStep) and linking a device: its steps
// (device_link_steps._Step), its card on either device (DeviceLinkQr,
// DeviceLinkApprovalForm, DeviceLinkImportForm) and the phone's camera (DeviceQrScanner).
card('Wizard step', 'A step asks for one thing. Its heading is the question, the line under it says why Mosh asks, and one primary button moves on; Back is always the quiet one under it. Setup is a real sequence of three, so it counts its steps: done ones are ticked, the current one is filled. Linking a device counts the same way inside its card, which is the same card in setup and in settings: the trusted device shows a QR and takes the code, the new one reads the QR and shows the code. A step opened from the start menu has no count, only the way back.');
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
/** The three steps of linking a device as [first] names the first of them, [at] the current one. The phone sets them closer, so the three keep to one line. */
function linkSteps(parent, Device, first, at) {
  const r = wrapRow(parent, 'link steps', Device === 'Phone' ? 2 : 4);
  [first, 'Confirm code', 'Link devices'].forEach((Label, i) => add(r, setProps(inst('Link step', { State: stateOf(i, at) }), { Label, Number: String(i + 1) })));
}
// A QR is read by a camera, so it keeps dark modules on a light plate in either theme: the inverse surface and its ink.
// The pattern only stands for a code: three finders and a scatter that is the same in every build.
await grid('QR code', ONE, ONE, () => {
  const N = 25, CELL = 8, finders = [[0, 0], [N - 7, 0], [0, N - 7]];
  const on = (x, y) => {
    const f = finders.find(([fx, fy]) => x >= fx - 1 && x < fx + 8 && y >= fy - 1 && y < fy + 8);
    if (!f) return Math.abs(Math.sin(x * 12.9898 + y * 78.233) * 43758.5453) % 1 < 0.48;
    const dx = x - f[0], dy = y - f[1], ring = Math.max(Math.abs(dx - 3), Math.abs(dy - 3));
    return ring === 3 || ring < 2;
  };
  const cells = [];
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) if (on(x, y)) cells.push(`M ${x * CELL} ${y * CELL} L ${(x + 1) * CELL} ${y * CELL} L ${(x + 1) * CELL} ${(y + 1) * CELL} L ${x * CELL} ${(y + 1) * CELL} Z`);
  const q = box('QR code', { component: true, pad: 4, r: 'medium', fill: 'inverseSurface' });
  const modules = figma.createVector();
  modules.name = 'modules'; modules.vectorPaths = [{ windingRule: 'NONZERO', data: cells.join(' ') }]; modules.strokes = []; modules.fills = paint('onInverseSurface');
  add(q, modules);
  return q;
});
// A code one device shows and the other takes: set apart on a plate, in type large enough to read across a desk.
const codes = await grid('Code plate', ONE, ONE, () => {
  const p = inset('Code plate', { component: true, dir: 'V', gap: 1, pad: 4, w: 320 });
  add(p, text('Confirmation code', 'labelMedium', 'onSurfaceVariant', { name: 'label' }));
  add(p, text('K7Q2 M9XD 4PLA', 'headlineMedium', 'onSurface', { name: 'code' }));
  return p;
});
prop(codes, 'Label', 'TEXT', 'Confirmation code', 'label');
prop(codes, 'Code', 'TEXT', 'K7Q2 M9XD 4PLA', 'code');
const field = (Device, values = {}) => setProps(inst('Text field', { State: 'Default', Device }), values);
const CONNECT = ['qr', 'Connect this device'], LINK = ['devices', 'Link another device'];
// Per kind: what the card holds over its way out. The new device reads the QR and shows the code; the trusted one shows the QR and takes the code.
const LINKS = {
  'Read QR': (c, Device) => {
    header(c, ...CONNECT, 'On the device you already use, open Settings, Devices, Link another device. Read its QR here, then show it your confirmation code.');
    linkSteps(c, Device, 'Read QR', 0);
    // Only the phone has a camera to point at the other screen. No way to read the QR is the primary one: in setup that is the button under the card.
    if (Device === 'Phone') add(c, labelButton(Device, 'Scan with camera', { Kind: 'Outlined', glyph: 'scan' }), { fillW: true });
    add(c, labelButton(Device, 'Choose QR image', { Kind: 'Outlined', glyph: 'image' }), { fillW: true });
    // The link is sent with the button beside its field, level with the well under the label.
    const paste = add(c, box('paste', { dir: 'H', gap: 2, align: 'MAX' }), { fillW: true });
    add(paste, field(Device, { Label: 'Paste the link from your trusted device', Placeholder: 'mosh://device-link/…' }), { fillW: true });
    add(paste, action('forward', Device, { Kind: 'Tonal' })).name = 'send link';
  },
  'Show code': (c, Device) => {
    header(c, ...CONNECT, 'Enter this code on your trusted device to approve this one');
    linkSteps(c, Device, 'Read QR', 1);
    add(c, inst('Code plate'), { fillW: true });
  },
  'Show QR': (c, Device) => {
    header(c, ...LINK, 'Scan this QR on the new device. You will confirm its code here before it gets access.');
    linkSteps(c, Device, 'Show QR', 0);
    const q = add(c, box('code', { dir: 'V', gap: 2 }), { fillW: true });
    add(q, inst('QR code'));
    add(q, labelButton(Device, 'Copy link', { Kind: 'Text', glyph: 'copy' }));
    para(c, 'This QR expires after five minutes. Do not share it with anyone else.', 'bodySmall', 'onSurfaceVariant', 'note');
  },
  'Enter code': (c, Device) => {
    header(c, ...LINK, 'Enter the code shown on the device you want to link. Approve only a device you control.');
    linkSteps(c, Device, 'Show QR', 1);
    add(c, text('Studio MacBook Air', 'titleSmall', 'onSurface', { name: 'device' }));
    add(c, field(Device, { Label: 'Code from the new device', Placeholder: '12 characters' }), { fillW: true });
    add(c, labelButton(Device, 'Approve device'), { fillW: true });
  },
};
const linkCards = display(await grid('Link card', axis('Kind', Object.keys(LINKS)), DEVICES, ({ Kind, Device }) => {
  const c = cardSurface('Link card', { component: true, dir: 'V', gap: 4, pad: cardPad(Device), w: CARD_W[Device], align: 'MIN' });
  LINKS[Kind](c, Device);
  add(c, labelButton(Device, 'Cancel link', { Kind: 'Text' })).name = 'cancel';
  return c;
}));
// Setup has its own way back, so its card can go without one.
prop(linkCards, 'Cancel', 'BOOLEAN', true, 'cancel');
/** The question a step asks and why Mosh asks it. */
function question(parent, title, lead, centred) {
  const h = add(parent, box('question', { dir: 'V', gap: 2, align: centred ? 'CENTER' : 'MIN' }), { fillW: true });
  titled(h, [title, 'headlineMedium', 'onSurface'], [lead, 'bodyLarge', 'onSurfaceVariant'], centred);
}
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
    add(s, setProps(inst('Link card', { Kind: 'Read QR', Device }), { Cancel: false }), { fillW: true });
    add(s, labelButton(Device, 'This is my first device'), { fillW: true });
    add(s, labelButton(Device, 'Back', { Kind: 'Text' }));
  },
  'Setup network': (s, Device) => {
    add(s, inst('Setup progress', { Step: '3', Device }));
    question(s, 'Choose your connection', 'Use the system connection, or choose a physical network interface if a VPN interferes with discovery.');
    add(s, setProps(inst('Select', { State: 'Closed', Device }), { Label: 'Connection', Value: 'Automatic, system connection' }), { fillW: true });
    para(s, 'Mosh follows your system routing, including an active VPN.', 'bodySmall', 'onSurfaceVariant', 'note');
    add(s, labelButton(Device, 'Save and finish'), { fillW: true });
    add(s, labelButton(Device, 'Back', { Kind: 'Text' }));
  },
  'Start menu step': (s, Device) => {
    add(add(s, box('back', { dir: 'H' }), { fillW: true }), labelButton(Device, 'Back', { Kind: 'Text', glyph: 'back' }));
    question(s, 'Join a public channel', 'Join an open room by its name', true);
    const c = add(s, cardSurface('channel card', { dir: 'V', gap: 4, pad: cardPad(Device) }), { fillW: true });
    add(c, inst('Inline note', { Kind: 'Open channel', Device }), { fillW: true });
    add(c, field(Device, { Label: 'Channel name', Placeholder: 'Latin letters, digits, - and _', Icon: true, 'Icon glyph': glyphOf('tag') }), { fillW: true });
    add(c, labelButton(Device, 'Join channel', { State: 'Disabled' }), { fillW: true });
    const tips = add(c, box('examples', { dir: 'H', gap: 2 }));
    add(tips, text('For example', 'labelMedium', 'onSurfaceMuted'));
    ['news', 'dev', 'community'].forEach((Label) => add(tips, setProps(inst('Suggestion chip', { State: 'Default', Device }), { Label: '#' + Label })));
  },
  // The new device has read the QR: it shows its code, and can still leave the link and go on alone.
  'Setup device code': (s, Device) => {
    add(s, inst('Setup progress', { Step: '2', Device }));
    question(s, 'Set up this device', 'Start here if this is your first device, or connect it to the Mosh you already use.');
    add(s, setProps(inst('Link card', { Kind: 'Show code', Device }), { Cancel: false }), { fillW: true });
    add(s, labelButton(Device, 'Cancel linking and continue independently', { Kind: 'Text' }));
  },
};
display(await grid('Wizard step', axis('Kind', Object.keys(STEPS)), DEVICES, ({ Kind, Device }) => {
  const s = surface('Wizard step', 'background', { component: true, dir: 'V', gap: 5, pad: Device === 'Phone' ? 4 : 6, w: STEP_W[Device] + px('space/' + (Device === 'Phone' ? 4 : 6)) * 2 });
  STEPS[Kind](s, Device);
  return s;
}));

// The phone reads the QR with its camera: the picture is the screen, and what to do with it stands under the picture.
// Per state: the mark and title that stand in for a picture the camera cannot give, and the line about it.
const SCANS = {
  'Camera open': [null, null, 'Point the camera at the QR on your trusted device'],
  'Camera denied': ['video_off', 'Mosh cannot use the camera', 'Allow camera access in Android settings, or return to choose a QR image or paste the link'],
  'No camera': ['video_off', 'The camera is unavailable', 'Return to choose a QR image or paste the link'],
};
display(await grid('Scanner', ONE, axis('State', Object.keys(SCANS)), ({ State }) => {
  const [glyph, title, line] = SCANS[State];
  const s = box('Scanner', { component: true, dir: 'V', pad: [1, 4, 4, 4], w: PHONE_SCREEN, h: 844, fill: BENEATH, clip: true });
  add(s, setProps(inst('Page header', { Device: 'Phone' }), { Title: 'Scan QR with camera', 'Show line': false }), { fillW: true });
  const view = add(s, box('view', { dir: 'V', gap: 3, justify: 'CENTER' }), { fillW: true, fillH: true });
  const foot = add(s, cardSurface('foot', { dir: 'V', gap: 1, pad: 4 }), { fillW: true });
  if (glyph) {
    add(view, icon(glyph, 'onSurfaceVariant', 10));
    titled(add(view, box('text', { dir: 'V', gap: 1, w: 280 })), [title, 'titleMedium', 'onSurface'], [line, 'bodyMedium', 'onSurfaceVariant'], true);
  } else {
    add(view, box('finder', { w: 240, h: 240, r: 'large', stroke: 'onSurface', sw: 'thick' }));
    para(foot, line, 'bodyMedium', 'onSurface', 'line').textAlignHorizontal = 'CENTER';
  }
  add(foot, labelButton('Phone', 'Use an image or link', { Kind: 'Text' }));
  return s;
}));
