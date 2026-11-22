// Publishes the component inventory (inventory.mjs) to the Figma file: one
// "Components inventory" section on the Redesign page, a card per component
// with its counts, states and example crops linked to their frames.
import fs from 'node:fs';
import path from 'node:path';
import { PNG } from 'pngjs';
import { PAGES } from './areas.mjs';
import { GROUPS, SCREEN_GROUP, SCREEN_PARTS } from './components.mjs';
import { execute } from './mcp.mjs';
import { themeTokens, windowColor } from './tokens.mjs';

const PAGE = 'Redesign';
const SECTION = 'Components inventory';
const THUMB = { w: 360, h: 220 };

/** Figma frame of every rendered scene; throws when Figma lacks one, since links would point at an older capture. */
export async function frameIds(scenes) {
  const { fileKey, ids } = await execute(`
    await figma.loadAllPagesAsync();
    const pages = new Set(${JSON.stringify(Object.values(PAGES).map((p) => p.page))});
    const ids = {};
    for (const p of figma.root.children) if (pages.has(p.name))
      for (const s of p.children) if (s.type === 'SECTION')
        for (const f of s.children) { const id = f.getPluginData('sceneId'); if (id) ids[id] = f.id; }
    return { fileKey: figma.fileKey, ids };`);
  const missing = scenes.filter((s) => !ids[s.id]).map((s) => s.id);
  if (missing.length) throw new Error(`Figma has no frame for ${missing.length} rendered scenes (publish them first): ${missing.slice(0, 5).join(', ')}`);
  return { node: (sceneId) => ids[sceneId], url: (sceneId) => `https://www.figma.com/design/${fileKey}/Mosh?node-id=${ids[sceneId].replace(':', '-')}` };
}

/** [rect] of the scene's reference render on the window colour, as base64 PNG. */
function crop(scene, rect) {
  const src = PNG.sync.read(fs.readFileSync(path.join(scene.dir, 'ref.png')));
  const pad = 12;
  const x0 = Math.max(0, Math.floor(rect.x - pad)), y0 = Math.max(0, Math.floor(rect.y - pad));
  const x1 = Math.min(src.width, Math.ceil(rect.x + rect.w + pad)), y1 = Math.min(src.height, Math.ceil(rect.y + rect.h + pad));
  const out = new PNG({ width: x1 - x0, height: y1 - y0 });
  const bg = windowColor().map((v) => v * 255);
  for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) {
    const i = (y * src.width + x) * 4, o = ((y - y0) * out.width + (x - x0)) * 4, a = src.data[i + 3] / 255;
    for (let c = 0; c < 3; c++) out.data[o + c] = Math.round(src.data[i + c] * a + bg[c] * (1 - a));
    out.data[o + 3] = 255;
  }
  return { png: PNG.sync.write(out).toString('base64'), w: out.width, h: out.height };
}

// Plugin helpers shared by every call: the section, fonts and token paints.
const PRELUDE = `
  await figma.loadAllPagesAsync();
  const page = figma.root.children.find((p) => p.name === ${JSON.stringify(PAGE)});
  if (!page) throw new Error('no ${PAGE} page');
  const family = ${JSON.stringify(themeTokens().family)};
  for (const style of ['Regular', 'SemiBold']) await figma.loadFontAsync({ family, style });
  const dark = (await figma.variables.getLocalVariableCollectionsAsync()).find((c) => c.name === 'Mosh');
  const vars = (await figma.variables.getLocalVariablesAsync('COLOR')).filter((v) => v.variableCollectionId === dark?.id);
  const paint = (name) => {
    const v = vars.find((x) => x.name === name);
    if (!v) throw new Error('no colour variable ' + name);
    return [figma.variables.setBoundVariableForPaint({ type: 'SOLID', color: { r: 0, g: 0, b: 0 } }, 'color', v)];
  };
  const text = (parent, chars, size, style = 'Regular', color = 'surface/onSurface') => {
    const t = figma.createText();
    t.fontName = { family, style }; t.fontSize = size; t.characters = chars; t.fills = paint(color);
    parent.appendChild(t);
    return t;
  };
  const stack = (parent, name, dir, gap) => {
    const f = figma.createFrame();
    f.name = name; f.layoutMode = dir; f.itemSpacing = gap; f.fills = [];
    f.primaryAxisSizingMode = 'AUTO'; f.counterAxisSizingMode = 'AUTO';
    parent.appendChild(f);
    return f;
  };`;

// The section stays put, so links to it survive a rebuild. New cards go into a
// draft beside the published content, which the draft replaces only once every
// card is in, so a failed run leaves the old content whole.
const SECTION_NODE = `page.children.find((s) => s.getPluginData('inventory') === 'section')`;
const content = (mark) => `section.children.find((c) => c.getPluginData('inventory') === '${mark}')`;

/** Starts a draft holding a column per group, creating the section on the first run; returns nothing. */
const startDraft = (groups) => execute(`${PRELUDE}
  let section = ${SECTION_NODE};
  if (!section) {
    const bottom = Math.max(0, ...page.children.map((c) => c.y + c.height));
    section = figma.createSection();
    page.appendChild(section);
    section.name = ${JSON.stringify(SECTION)};
    section.setPluginData('inventory', 'section');
    section.fills = paint('surface/surface');
    section.x = 0; section.y = bottom + 400;
  }
  ${content('draft')}?.remove();
  const root = stack(section, ${JSON.stringify(SECTION)}, 'HORIZONTAL', 120);
  root.setPluginData('inventory', 'draft');
  root.x = 100; root.y = Math.max(100, ...section.children.filter((c) => c !== root).map((c) => c.y + c.height + 400));
  for (const g of ${JSON.stringify(groups)}) {
    const col = stack(root, g.title, 'VERTICAL', 32);
    col.setPluginData('inventory', g.id);
    text(col, g.title + ' · ' + g.ticket, 40, 'SemiBold');
  }`);

// Appends one card to its group's column in the draft.
const CARD = `${PRELUDE}
  const section = ${SECTION_NODE};
  const root = ${content('draft')};
  const col = root.children.find((c) => c.getPluginData('inventory') === C.group);
  const card = stack(col, C.name, 'VERTICAL', 12);
  card.fills = paint('surface/surfaceContainer'); card.cornerRadius = 16;
  card.paddingLeft = card.paddingRight = card.paddingTop = card.paddingBottom = 24;
  card.counterAxisSizingMode = 'FIXED'; card.resize(${THUMB.w * 3 + 24 * 2 + 16 * 2}, card.height);
  text(card, C.name, 24, 'SemiBold');
  text(card, C.meta, 14, 'Regular', 'surface/onSurfaceVariant');
  for (const s of C.states) { const t = text(card, s, 14); t.layoutAlign = 'STRETCH'; t.textAutoResize = 'HEIGHT'; }
  const row = stack(card, 'examples', 'HORIZONTAL', 16);
  for (const e of C.examples) {
    const cell = stack(row, e.caption, 'VERTICAL', 8);
    const img = figma.createRectangle();
    img.name = e.caption; img.resize(e.w, e.h); img.cornerRadius = 8;
    img.fills = [{ type: 'IMAGE', scaleMode: 'FIT', imageHash: figma.createImage(figma.base64Decode(e.png)).hash }];
    cell.appendChild(img);
    const t = text(cell, e.caption, 12, 'Regular', 'surface/onSurfaceVariant');
    t.resize(${THUMB.w}, t.height); t.textAutoResize = 'HEIGHT';
    t.hyperlink = { type: 'NODE', value: e.node }; t.textDecoration = 'UNDERLINE';
  }
`;

/** Replaces the published content with the finished draft and fits the section to it. */
const publishDraft = () => execute(`${PRELUDE}
  const section = ${SECTION_NODE};
  const root = ${content('draft')};
  ${content('root')}?.remove();
  root.setPluginData('inventory', 'root');
  root.x = 100; root.y = 100;
  section.resizeWithoutConstraints(root.width + 200, root.height + 200);`);

/** Fits a crop into the thumbnail box without enlarging it. */
const fit = ({ w, h }) => {
  const k = Math.min(1, THUMB.w / w, THUMB.h / h);
  return { w: Math.round(w * k), h: Math.round(h * k) };
};

/** Rebuilds the section from [components] (inventory.mjs summaries), linking examples through [ids] (frameIds). */
export async function publishInventory({ components, ids }) {
  const cards = [
    ...components.map((c) => ({
      group: c.group, name: c.name, states: c.states,
      meta: `${c.frames} frames · ${c.instances} instances`,
      examples: c.examples.map((e) => {
        const { png, ...size } = crop(e.scene, e.rect);
        return { png, ...fit(size), node: ids.node(e.scene.id), caption: `${e.scene.title} · ${e.scene.form}` };
      }),
    })),
    { group: SCREEN_GROUP.id, name: SCREEN_GROUP.title, meta: 'Laid out per screen, not redrawn as components', states: [SCREEN_PARTS.join(', ')], examples: [] },
  ];
  await startDraft([...GROUPS, SCREEN_GROUP]);
  for (const c of cards) await execute(`const C = ${JSON.stringify(c)};\n${CARD}`);
  await publishDraft();
  console.log(`Figma: ${PAGE} / ${SECTION}: ${cards.length} cards`);
}
