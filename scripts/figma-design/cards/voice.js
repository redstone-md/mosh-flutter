// Voice: VoiceMessageCard with its VoiceWaveform and VoiceCardTimeLabel.
card('Voice message', 'One button plays and pauses, and the waveform fills as the message plays. While the audio is still arriving the button spins, and when it could not be loaded the button tries again. The capture shows the message at rest only; the other three states are new.');
// Bar heights of the sample waveform, px.
const BARS = [6, 10, 14, 8, 18, 22, 12, 16, 24, 14, 8, 12, 20, 16, 10, 6, 12, 18, 22, 14, 10, 16, 8, 12, 6, 10, 14, 8];
const PLAYED = 10;
const waves = await grid('Waveform', TONE_ROWS(ONE), axis('Progress', ['None', 'Part']), ({ Progress, Tone }) => {
  const c = TONES[Tone], w = box('Waveform', { component: true, dir: 'H', gap: 1, hk: 6 });
  BARS.forEach((h, i) => add(w, rect('bar', { fill: Progress === 'Part' && i < PLAYED ? c.accent : c.rest, w: 3, h, r: 'full' })));
  return w;
});
const VOICE = { Idle: ['play', '0:14'], Playing: ['pause', '0:05 of 0:14'], Loading: [null, 'Loading'], Failed: ['refresh', 'Could not load'] };
function voice({ State, Tone, Device }) {
  const c = TONES[Tone], [glyph, detail] = VOICE[State], key = Device === 'Phone' ? 12 : 10;
  const v = box('Voice message', { component: true, dir: 'H', gap: 3 });
  const button = add(v, box('button', { dir: 'H', wk: key, hk: key, r: 'full', fill: c.accent, justify: 'CENTER' }));
  add(button, glyph ? icon(glyph, c.onAccent) : spinner(c.onAccent, 5));
  const col = add(v, box('voice', { dir: 'V', gap: 1, align: 'MIN' }));
  add(col, inst('Waveform', { Progress: State === 'Playing' ? 'Part' : 'None', Tone }));
  add(col, text(detail, 'labelSmall', State === 'Failed' ? c.error : c.quiet, { name: 'detail ' + State }));
  return v;
}
const voices = backdrop(display(await grid('Voice message', perDevice(TONE_ROWS(ONE)), axis('State', Object.keys(VOICE)), voice)));
backdrop(waves);
for (const [s, [, detail]] of Object.entries(VOICE)) prop(voices, 'Detail, ' + s.toLowerCase(), 'TEXT', detail, 'detail ' + s);
