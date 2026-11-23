// Toasts: ToastCard, alone and stacked (ToastHost).
card('Toast', 'A toast confirms what just happened and leaves on its own; an error stays until it is closed. It floats on the popup level, at the top of the window on the desktop and above the bottom edge on the phone. The mark tells the tone and the text stays the ordinary colour, so a toast never reads as an alarm it is not. Several toasts stack behind the newest one and fan out under the pointer.');
const TOASTS = { Success: ['success', 'success', 'Link copied'], Info: ['info', 'onSurfaceVariant', 'Chat renamed'], Error: ['error', 'error', 'Mosh could not reach the network. Try again in a moment.'] };
const WIDTH = { Desktop: 360, Phone: 358 };
const toasts = display(await grid('Toast', axis('Tone', Object.keys(TOASTS)), DEVICES, ({ Tone, Device }) => {
  const [glyph, ink, message] = TOASTS[Tone];
  const t = surface('Toast', 'popup', { component: true, dir: 'H', gap: 3, pad: [1, 1, 1, 4], w: WIDTH[Device], minHk: 12, r: 'large' });
  add(t, icon(glyph, ink));
  add(add(t, box('text', { dir: 'V', pad: [2, 0] }), { fillW: true }), text(message, 'bodyMedium', 'onSurface', { name: Tone === 'Error' ? 'message, error' : 'message', w: 200 }), { fillW: true });
  add(t, action('close', Device)).name = 'close';
  return t;
}));
prop(toasts, 'Message', 'TEXT', 'Link copied', 'message');
prop(toasts, 'Message, error', 'TEXT', TOASTS.Error[2], 'message, error');

const QUEUE = [['Info', 'Chat renamed'], ['Success', 'Link copied'], ['Error', TOASTS.Error[2]]];
const toast = (Device, [Tone, message]) => setProps(inst('Toast', { Tone, Device }), { [Tone === 'Error' ? 'Message, error' : 'Message']: message });
/** Toasts behind the newest one: each a step narrower and a step lower, so only its bottom edge shows. */
function stack(Device) {
  const STEP = 8, front = toast(Device, QUEUE.at(-1));
  const s = box(`Stack · ${Device}`, { dir: 'V', w: WIDTH[Device], h: front.height + STEP * (QUEUE.length - 1) });
  s.layoutMode = 'NONE';
  QUEUE.forEach((q, i) => {
    const depth = QUEUE.length - 1 - i, t = i === QUEUE.length - 1 ? front : toast(Device, q);
    s.appendChild(t);
    t.resize(WIDTH[Device] - depth * STEP * 2, front.height); t.x = depth * STEP; t.y = depth * STEP;
  });
  return s;
}
function fanned(Device) {
  const s = box(`Stack under the pointer · ${Device}`, { dir: 'V', gap: 2, w: WIDTH[Device] });
  QUEUE.forEach((q) => add(s, toast(Device, q), { fillW: true }));
  return s;
}
await examples('A stack, and the stack under the pointer', [stack('Desktop'), fanned('Desktop'), stack('Phone')], 'MIN');
