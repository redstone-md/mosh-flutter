// The four surface levels of surfaces.js side by side, and the popups and
// modals of the cards before this one over real screens: the check that a
// surface reads as its level whatever lies under it.
card('Surface levels', 'Every surface sits on one of four levels, and takes its tone, its edge and its shadow from the level, never from a colour chosen on the spot. The background is the screen. A panel is a part of the screen. A popup floats until its choice is made and leaves the screen alive. A modal stops the screen: it always lies on the scrim, which is what tells it from a popup of the same tone.');
/** What a level is made of, read from LEVEL so the card cannot disagree with it. */
const recipe = ({ fill, stroke, effect }) => [fill, stroke && stroke + ' edge', effect].filter(Boolean).join(', ');
const NOTE = { panel: 'as a card, with an outlineVariant edge', modal: 'always on the scrim' };
const ladder = surface('Levels', 'background', { dir: 'H', gap: 6, pad: 6, align: 'MIN' });
for (const level of Object.keys(LEVEL)) {
  const s = add(ladder, level === 'panel' ? cardSurface(level, { dir: 'V', gap: 1, pad: 4, w: 220, h: 132, r: 'large', align: 'MIN' }) : surface(level, level, { dir: 'V', gap: 1, pad: 4, w: 220, h: 132, align: 'MIN' }));
  add(s, text(level[0].toUpperCase() + level.slice(1), 'titleSmall', 'onSurface'));
  para(s, [recipe(LEVEL[level]), NOTE[level]].filter(Boolean).join('; '), 'bodySmall', 'onSurfaceVariant');
}
await examples('The levels, lowest first', [ladder], 'MIN');

function stopped(name, Device, node, at) {
  const [w, h] = Device === 'Phone' ? [PHONE_SCREEN, 560] : [480, 400], screen = BACKDROPS[name](Device, w, h);
  dim(screen);
  return over(screen, node, at);
}
const confirm = (Device) => inst('Dialog', { Kind: 'Destructive', Device });
await examples('A dialog over a conversation, the chat list, settings and the media viewer', Object.keys(BACKDROPS).map((name) => stopped(name, 'Desktop', confirm('Desktop'))), 'MIN');
await examples('On the phone: a dialog and a sheet', [stopped('Conversation', 'Phone', confirm('Phone')), stopped('Settings', 'Phone', inst('Sheet', { Kind: 'Network adapter' }), 'bottom'), stopped('Media viewer', 'Phone', confirm('Phone'))], 'MIN');
const alive = (name, node, at) => over(BACKDROPS[name]('Desktop', 480, 400), node, at);
await examples('Popups leave the screen alive: a menu, a toast, a toast over the viewer', [alive('Conversation', inst('Menu', { Kind: 'Message', Device: 'Desktop' })), alive('Chat list', inst('Toast', { Tone: 'Success', Device: 'Desktop' }), 'top'), alive('Media viewer', inst('Toast', { Tone: 'Error', Device: 'Desktop' }), 'top')], 'MIN');
