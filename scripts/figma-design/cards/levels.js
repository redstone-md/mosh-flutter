// The four surface levels of surfaces.js side by side, and the popups and
// modals of the cards before this one over real screens: the check that a
// surface reads as its level whatever lies under it.
card('Surface levels', 'Every surface sits on one of four levels, and takes its tone, its edge and its shadow from the level, never from a colour chosen on the spot. The background is the screen. A panel is a part of the screen. A popup floats until its choice is made and leaves the screen alive. A modal stops the screen: it always lies on the scrim, which is what tells it from a popup of the same tone.');
const TOKENS_OF = { background: 'surface', panel: 'surfaceContainerLow, as a card with an outlineVariant edge', popup: 'surfaceContainerHigh, outlineVariant edge, elevation 2', modal: 'surfaceContainerHigh, outlineVariant edge, elevation 3, on the scrim' };
const ladder = surface('Levels', 'background', { dir: 'H', gap: 6, pad: 6, align: 'MIN' });
for (const level of Object.keys(LEVEL)) {
  const s = add(ladder, level === 'panel' ? cardSurface(level, { dir: 'V', gap: 1, pad: 4, w: 220, h: 132, r: 'large', align: 'MIN' }) : surface(level, level, { dir: 'V', gap: 1, pad: 4, w: 220, h: 132, r: level === 'background' ? null : 'large', align: 'MIN' }));
  add(s, text(level[0].toUpperCase() + level.slice(1), 'titleSmall', 'onSurface'));
  para(s, TOKENS_OF[level], 'bodySmall', 'onSurfaceVariant');
}
await examples('The levels, lowest first', [ladder], 'MIN');

const THREAD = [['Incoming', 'I booked the cabin near the lighthouse for two nights.'], ['Outgoing', 'Perfect. I will bring the camera and the thermos.'], ['Outgoing', 'Should we leave at 6 to beat the traffic?'], ['Incoming', 'Leo can drive. He has room for three and the gear.']];
// What a surface may have to lie over: each makes a screen of the given width and height.
const SCREENS = {
  Conversation: (Device, w, h) => {
    const f = surface('Conversation', 'background', { dir: 'V', w, h, clip: true, align: 'MIN' });
    add(f, inst('Top bar', { Kind: 'Private chat', Device }), { fillW: true });
    const feed = add(f, box('feed', { dir: 'V', gap: 1, pad: [3, feedPad(Device)], align: 'MIN' }), { fillW: true });
    for (const [side, Text] of THREAD) add(add(feed, box('place', { dir: 'H', justify: side === 'Outgoing' ? 'MAX' : 'MIN' }), { fillW: true }), setProps(inst(side + ' message', { Position: 'Single', Device, State: 'Default' }), { Text }));
    return f;
  },
  'Chat list': (Device, w, h) => {
    const f = surface('Chat list', 'panel', { dir: 'V', gap: 1, pad: [4, 2], w, h, clip: true });
    for (const State of ['Default', 'Selected', 'Default', 'Default', 'Default']) add(f, inst('Chat row', { State, Device }), { fillW: true });
    return f;
  },
  Settings: (Device, w, h) => {
    const f = surface('Settings', 'background', { dir: 'V', gap: 3, pad: 5, w, h, clip: true });
    for (const Kind of ['Switch and details', 'Control']) add(f, inst('Settings card', { Kind, Device }), { fillW: true });
    return f;
  },
  'Media viewer': (Device, w, h) => {
    const v = inst('Media viewer', { Kind: 'Image', Device });
    v.resize(w, h);
    const f = box('Media viewer', { dir: 'V', w, h, clip: true });
    add(f, v);
    return f;
  },
};
/** Lays [node] over [screen]: in its middle, or along its top or bottom edge. */
function over(screen, node, at = 'middle') {
  screen.appendChild(node);
  node.layoutPositioning = 'ABSOLUTE';
  if (at === 'bottom') node.resize(screen.width, node.height);
  node.x = (screen.width - node.width) / 2;
  node.y = at === 'bottom' ? screen.height - node.height : at === 'top' ? 16 : (screen.height - node.height) / 2;
  return screen;
}
function stopped(name, Device, node, at) {
  const [w, h] = Device === 'Phone' ? [SCREEN.Phone, 560] : [480, 400], screen = SCREENS[name](Device, w, h);
  dim(screen);
  return over(screen, node, at);
}
const confirm = (Device) => inst('Dialog', { Kind: 'Destructive', Device });
await examples('A dialog over a conversation, the chat list, settings and the media viewer', Object.keys(SCREENS).map((name) => stopped(name, 'Desktop', confirm('Desktop'))), 'MIN');
await examples('On the phone: a dialog and a sheet', [stopped('Conversation', 'Phone', confirm('Phone')), stopped('Settings', 'Phone', inst('Sheet', { Kind: 'Network adapter' }), 'bottom'), stopped('Media viewer', 'Phone', confirm('Phone'))], 'MIN');
const alive = (name, node, at) => over(SCREENS[name]('Desktop', 480, 400), node, at);
await examples('Popups leave the screen alive: a menu, a toast, a toast over the viewer', [alive('Conversation', inst('Menu', { Kind: 'Message', Device: 'Desktop' })), alive('Chat list', inst('Toast', { Tone: 'Success', Device: 'Desktop' }), 'top'), alive('Media viewer', inst('Toast', { Tone: 'Error', Device: 'Desktop' }), 'top')], 'MIN');
