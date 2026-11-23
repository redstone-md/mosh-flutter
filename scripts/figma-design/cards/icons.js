// Icons: one component per role in icons.json, drawn from ICON_SVG (build.mjs).
// The card is updated in place: a glyph is redrawn inside its existing
// component, so the instances inside the controls keep pointing at it.
const NOTE = 'Phosphor, regular weight; the Mosh+ mark is the filled cut. Each is a 24 px component whose glyph scales with the instance; controls recolour it and swap it through their Icon property.';
CARD = host().children.find((n) => n.name === 'Icons');
if (!CARD) {
  card('Icons', NOTE);
  const icons = box('Icons', { dir: 'H', gap: 4 });
  CARD.appendChild(icons); icons.x = PAD; icons.y = cursor;
  await flush();
}
CARD.setPluginData('script', CARD_SCRIPT);
const row = CARD.children.find((n) => n.type === 'FRAME');
CARD.children[1].characters = NOTE;
// A role taken out of icons.json leaves the file too.
for (const [name, comp] of Object.entries(ICONS)) if (!ICON_SVG[name]) { comp.remove(); delete ICONS[name]; }
for (const [name, source] of Object.entries(ICON_SVG)) {
  // An unchanged glyph is left alone: redrawing it drops the colour overrides of its instances.
  if (ICONS[name]?.getPluginData('svg') === source) continue;
  const frame = figma.createNodeFromSvg(source);
  const glyph = figma.flatten(frame.findAll((n) => n.type === 'VECTOR' || n.type === 'BOOLEAN_OPERATION'), frame);
  let comp = ICONS[name];
  if (!comp) { comp = figma.createComponent(); comp.name = 'Icon/' + name; comp.fills = []; comp.resize(24, 24); size(comp, 6, 6); row.appendChild(comp); }
  comp.children.forEach((k) => k.remove());
  const at = [glyph.x, glyph.y];
  comp.appendChild(glyph);
  [glyph.x, glyph.y] = at;
  glyph.name = 'glyph'; glyph.fills = paint('onSurfaceVariant'); glyph.strokes = []; glyph.constraints = { horizontal: 'SCALE', vertical: 'SCALE' };
  comp.setPluginData('svg', source);
  frame.remove();
}
CARD.resize(Math.max(960, row.width + PAD * 2), row.y + row.height + PAD);
