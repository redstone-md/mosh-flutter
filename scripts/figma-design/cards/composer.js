// Composer: ConversationComposer with its attach button (AttachmentPicker), VoiceComposer,
// VoiceRecordingDot and the TypingHint above it.
card('Composer', 'One field for everything a person sends. Send lights up once there is something to send. Past the limit the field turns red and counts the characters to cut. A voice recording takes over the whole field: send it as it is, cancel it, or pause to hear it first. A paused recording can be played, sent or thrown away.');
const TEXT = { Empty: ['Write a message', 'onSurfaceMuted'], Draft: ['We have two. Packing them now', 'onSurface'], 'Over the limit': ['Anything else we need?', 'onSurface'], Disabled: ['Write a message', 'onSurface'] };
/** The send button; a 40 px plate, in a 48 px target on the phone. */
function send(Device, on) {
  const target = box('send', { dir: 'H', minWk: Device === 'Phone' ? 12 : null, minHk: Device === 'Phone' ? 12 : null, justify: 'CENTER' });
  const plate = add(target, box('plate', { dir: 'H', wk: 10, hk: 10, r: 'full', clip: true, fill: on ? 'primary' : null, justify: 'CENTER' }));
  const mark = add(plate, icon('send', on ? 'onPrimary' : 'onSurface'));
  if (!on) disable(plate, [mark], true);
  return target;
}
function composer({ State, Device }) {
  const off = State === 'Disabled', over = State === 'Over the limit';
  const c = box('Composer', { component: true, dir: 'H', gap: 1, pad: 1, w: FEED[Device] - 32, r: 'extraLarge', fill: 'surfaceContainerHigh', stroke: over ? 'error' : null });
  if (State === 'Recording') {
    // As in Telegram's locked recording: the clock, Cancel to throw it away, pause to hear it first, and send.
    const timer = add(c, box('timer', { dir: 'H', gap: 2, pad: [0, 4] }), { fillW: true });
    add(timer, dot('recording', 'error', 2));
    add(timer, text('0:04', 'labelLarge', 'onSurface', { name: 'time' }));
    add(c, setProps(inst('Button', { Kind: 'Text', Device, State: 'Default' }), { Label: 'Cancel' }));
    add(c, action('pause', Device));
    add(c, send(Device, true));
    return c;
  }
  if (State === 'Recorded') {
    add(c, action('delete', Device));
    // The recording itself: press it to listen. The waveform is cut where the capsule ends.
    const take = add(c, box('recording', { dir: 'H', gap: 2, pad: [0, 3], hk: 10, r: 'full', fill: 'surfaceContainerHighest' }), { fillW: true });
    add(take, icon('play', 'onSurface'));
    add(add(take, box('wave', { dir: 'H', hk: 6, clip: true }), { fillW: true }), inst('Waveform', { Progress: 'None', Tone: 'Surface' }));
    add(take, text('0:04', 'labelMedium', 'onSurfaceVariant', { name: 'time' }));
    add(c, send(Device, true));
    return c;
  }
  add(c, action('attach', Device, { State: off ? 'Disabled' : 'Default' }));
  add(c, action('mic', Device, { State: off ? 'Disabled' : 'Default' }));
  const [chars, ink] = TEXT[State];
  const field = add(c, text(chars, 'bodyLarge', ink, { name: 'text ' + State, truncate: true }), { fillW: true });
  if (off) bind(field, 'opacity', 'state/disabledContent');
  if (over) add(add(c, box('count', { dir: 'H', pad: [0, 2] })), text('-19', 'labelLarge', 'error', { name: 'over' }));
  add(c, send(Device, State === 'Draft'));
  return c;
}
const set = display(await grid('Composer', axis('State', [...Object.keys(TEXT), 'Recording', 'Recorded']), DEVICES, composer));
prop(set, 'Draft', 'TEXT', TEXT.Draft[0], 'text Draft');
prop(set, 'Time', 'TEXT', '0:04', 'time');
prop(set, 'Over by', 'TEXT', '-19', 'over');
const typing = await grid('Typing hint', ONE, ONE, () => {
  const t = box('Typing hint', { component: true, dir: 'H', pad: [1, 4] });
  add(t, text('Maya Chen is typing', 'labelMedium', 'onSurfaceMuted', { name: 'who', cut: true }), { max: MEASURE.Phone });
  return t;
});
prop(typing, 'Who', 'TEXT', 'Maya Chen is typing', 'who');
