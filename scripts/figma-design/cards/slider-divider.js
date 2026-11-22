// Slider (audio position in the media viewer) and Divider.
card('Slider and divider', 'The slider scrubs through audio: the played part is saffron, and the thumb grows under the pointer and the finger. The divider is a hairline that separates groups, never rows of the same list.');
function slider({ State, Device }) {
  const off = State === 'Disabled', ink = off ? 'onSurface' : 'primary';
  const s = box('slider', { dir: 'H', w: 240, hk: 6 });
  const played = add(s, rect('played', { fill: ink, w: 96, hk: 1, r: 'full' }));
  const thumb = add(s, dot('thumb', ink, { Hover: 5, Pressed: 6 }[State] ?? 4));
  if (State === 'Focus') focusRing(thumb);
  add(s, rect('rest', { fill: 'surfaceContainerHighest', hk: 1, r: 'full' }), { fillW: true });
  if (off) disable(s, [played, thumb]);
  return shell('Slider', s, Device);
}
await grid('Slider', perDevice(), STATES5, slider);
await grid('Divider', ONE, axis('Orientation', ['Horizontal', 'Vertical']), ({ Orientation }) => {
  const flat = Orientation === 'Horizontal';
  const d = box('Divider', { component: true, dir: flat ? 'H' : 'V', w: flat ? 240 : 1, h: flat ? 1 : 40, fill: 'outlineVariant' });
  bind(d, flat ? 'height' : 'width', 'border/thin');
  return d;
});
