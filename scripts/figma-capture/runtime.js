// Runs inside Figma (figma_execute). Expects a global-like `D` defined before it:
// { id, title, section, sectionIndex, slot, tree, images: {key: base64} }.
const W = { 100: 'Regular', 200: 'Regular', 300: 'Regular', 400: 'Regular', 500: 'Medium', 600: 'Semi Bold', 700: 'Bold', 800: 'Bold', 900: 'Bold' };
const fontOf = (run) => run.family === 'monospace'
  ? { family: 'Roboto Mono', style: run.weight >= 600 ? 'Bold' : run.weight >= 500 ? 'Medium' : 'Regular' }
  : { family: 'Inter', style: (W[run.weight] ?? 'Regular') + '' };
const fonts = new Map();
(function collect(n) {
  if (n.k === 'text') for (const r of n.runs) { const f = fontOf(r); fonts.set(f.family + f.style, f); }
  for (const k of n.kids ?? []) collect(k);
})(D.tree);
for (const f of fonts.values()) await figma.loadFontAsync(f);

// A colour binds to a variable only when every channel matches within half a level.
const colorVars = [];
for (const v of await figma.variables.getLocalVariablesAsync('COLOR')) {
  const val = Object.values(v.valuesByMode)[0];
  if (val && 'r' in val) colorVars.push([v, [val.r, val.g, val.b, val.a]]);
}
const varFor = (c) => colorVars.find(([, vc]) => vc.every((x, i) => Math.abs(x - c[i]) < 0.5 / 255))?.[0];
const textStyles = (await figma.getLocalTextStylesAsync()).filter((s) => s.name.startsWith('Mosh/'));
const styleFor = (run) => textStyles.find((s) => run.family !== 'monospace' && s.fontSize === run.size &&
  s.fontName.style === fontOf(run).style && Math.abs(s.lineHeight.value - (run.height ?? 0) * 100) < 0.5 &&
  Math.abs(s.letterSpacing.value - (run.ls ?? 0)) < 0.02);

function solid(c) {
  const v = varFor(c);
  const p = { type: 'SOLID', color: { r: c[0], g: c[1], b: c[2] }, opacity: c[3] };
  return v ? figma.variables.setBoundVariableForPaint({ ...p, opacity: 1 }, 'color', v) : p;
}
function gradient(g) {
  const [sx, sy] = g.begin.map((v) => (v + 1) / 2), [ex, ey] = g.end.map((v) => (v + 1) / 2);
  const dx = ex - sx, dy = ey - sy, l2 = dx * dx + dy * dy || 1;
  const n = g.colors.length;
  return {
    type: 'GRADIENT_LINEAR',
    gradientTransform: [[dx / l2, dy / l2, -(sx * dx + sy * dy) / l2], [-dy / l2, dx / l2, 0.5 + (sx * dy - sy * dx) / l2]],
    gradientStops: g.colors.map((c, i) => ({ position: g.stops?.[i] ?? (n === 1 ? 0 : i / (n - 1)), color: { r: c[0], g: c[1], b: c[2], a: c[3] } })),
  };
}
function effects(n) {
  const out = [];
  for (const e of n.effects ?? []) out.push({ type: 'DROP_SHADOW', color: { r: e.color[0], g: e.color[1], b: e.color[2], a: e.color[3] }, offset: e.offset, radius: e.radius, spread: 0, visible: true, blendMode: 'NORMAL' });
  if (n.blur) out.push({ type: 'LAYER_BLUR', radius: n.blur * 2, visible: true });
  return out;
}
function box(node, n) {
  node.fills = n.gradient ? [gradient(n.gradient)] : n.fill ? [solid(n.fill)] : [];
  if (n.stroke) { node.strokes = [solid(n.stroke)]; node.strokeWeight = n.sw; node.strokeAlign = n.inside ? 'INSIDE' : 'CENTER'; }
  if (n.radii && 'topLeftRadius' in node) [node.topLeftRadius, node.topRightRadius, node.bottomRightRadius, node.bottomLeftRadius] = n.radii;
  else if (n.radius && 'cornerRadius' in node) node.cornerRadius = n.radius;
  const fx = effects(n);
  if (fx.length) node.effects = fx;
}
const size = (node, r) => node.resize(Math.max(r.w, 0.01), Math.max(r.h, 0.01));
const rel = (d, ox, oy) => d.replace(/([ML])(-?[\d.]+) (-?[\d.]+)/g, (_, c, x, y) => `${c} ${(+x - ox).toFixed(2)} ${(+y - oy).toFixed(2)}`);
const hex = (c) => '#' + c.slice(0, 3).map((v) => Math.round(v * 255).toString(16).padStart(2, '0')).join('');

async function make(n, parent, ox, oy) {
  let node;
  switch (n.k) {
    case 'frame': {
      node = figma.createFrame();
      node.name = n.name ?? 'frame';
      size(node, n.r);
      box(node, n);
      if (n.ellipse) node.cornerRadius = Math.min(n.r.w, n.r.h) / 2;
      node.clipsContent = !!n.clip;
      parent.appendChild(node);
      for (const k of n.kids) await make(k, node, n.r.x, n.r.y);
      break;
    }
    case 'rect': case 'ellipse': {
      node = n.k === 'rect' ? figma.createRectangle() : figma.createEllipse();
      node.name = n.k === 'rect' ? 'rect' : 'ellipse';
      size(node, n.r); box(node, n);
      parent.appendChild(node);
      break;
    }
    case 'backdrop': {
      // Figma blurs what is behind a layer only through a translucent fill.
      node = figma.createRectangle();
      node.name = 'backdrop blur';
      size(node, n.r);
      node.fills = [{ type: 'SOLID', color: { r: 0, g: 0, b: 0 }, opacity: 0.01 }];
      node.effects = [{ type: 'BACKGROUND_BLUR', radius: n.blur * 2, visible: true }];
      parent.appendChild(node);
      break;
    }
    case 'image': {
      node = figma.createRectangle();
      node.name = 'image';
      size(node, n.r);
      const b64 = D.images[n.img];
      node.fills = b64 ? [{ type: 'IMAGE', scaleMode: 'FILL', imageHash: figma.createImage(figma.base64Decode(b64)).hash }] : [];
      node.opacity = n.opacity ?? 1;
      parent.appendChild(node);
      break;
    }
    case 'icon': {
      node = figma.createNodeFromSvg(`<svg xmlns="http://www.w3.org/2000/svg" width="${n.r.w}" height="${n.r.h}" viewBox="0 0 ${n.r.w} ${n.r.h}"><path d="${n.d}" fill="${hex(n.color)}"${n.rot ? ` transform="rotate(${n.rot} ${n.size / 2} ${n.size / 2})"` : ''}/></svg>`);
      node.name = 'icon/' + n.name;
      node.fills = [];
      for (const v of node.findAll((x) => x.type === 'VECTOR')) { v.fills = [solid(n.color)]; v.name = n.name; }
      parent.appendChild(node);
      break;
    }
    case 'path': {
      node = figma.createVector();
      node.name = 'path';
      parent.appendChild(node);
      // Several contours (outline glyphs, rings) are holes in Flutter's output.
      node.vectorPaths = [{ windingRule: (n.d.match(/M/g) ?? []).length > 1 ? 'EVENODD' : 'NONZERO', data: rel(n.d, n.r.x, n.r.y) }];
      node.fills = n.fill ? [solid(n.fill)] : [];
      node.strokes = n.stroke ? [solid(n.stroke)] : [];
      if (n.stroke) node.strokeWeight = n.sw;
      break;
    }
    case 'text': {
      node = figma.createText();
      parent.appendChild(node);
      const r0 = n.runs[0];
      node.fontName = fontOf(r0);
      node.characters = n.text;
      for (const run of n.runs) {
        const s = Math.min(run.s, n.text.length), e = Math.min(run.e, n.text.length);
        if (s >= e) continue;
        const style = styleFor(run);
        if (style) await node.setRangeTextStyleIdAsync(s, e, style.id);
        else {
          node.setRangeFontName(s, e, fontOf(run));
          node.setRangeFontSize(s, e, run.size);
          node.setRangeLineHeight(s, e, run.height ? { unit: 'PERCENT', value: run.height * 100 } : { unit: 'AUTO' });
          node.setRangeLetterSpacing(s, e, { unit: 'PIXELS', value: run.ls ?? 0 });
        }
        node.setRangeFills(s, e, [solid(run.color)]);
        if (run.underline) node.setRangeTextDecoration(s, e, 'UNDERLINE');
        if (run.strike) node.setRangeTextDecoration(s, e, 'STRIKETHROUGH');
      }
      node.textAlignHorizontal = { center: 'CENTER', right: 'RIGHT', end: 'RIGHT', justify: 'JUSTIFIED' }[n.align] ?? 'LEFT';
      if (n.ellipsis) {
        node.textAutoResize = 'NONE'; size(node, n.r);
        node.textTruncation = 'ENDING'; node.maxLines = n.ellipsis;
      } else if (n.lines <= 1) node.textAutoResize = 'WIDTH_AND_HEIGHT';
      else { node.textAutoResize = 'HEIGHT'; node.resize(n.r.w + 1, n.r.h); }
      node.name = n.text.slice(0, 40);
      break;
    }
    default: return;
  }
  node.x = n.r.x - ox;
  node.y = n.r.y - oy;
  return node;
}

await figma.loadAllPagesAsync();
const page = figma.root.children.find((p) => p.name === D.page) ?? (() => { const p = figma.createPage(); p.name = D.page; return p; })();
let section = page.children.find((s) => s.type === 'SECTION' && s.getPluginData('section') === D.section);
if (!section) {
  section = figma.createSection();
  page.appendChild(section);
  section.name = D.section;
  section.setPluginData('section', D.section);
}
const GAP = 120, PAD = 100, TITLE = 80, COLS = D.cols;
const sw = D.tree.r.w, sh = D.tree.r.h;
const col = D.slot % COLS, row = Math.floor(D.slot / COLS);
const old = section.children.find((c) => c.getPluginData('sceneId') === D.id);
if (old) old.remove();
const screen = await make(D.tree, section, -PAD - col * (sw + GAP), -PAD - TITLE - row * (sh + GAP + 40));
screen.name = D.title;
screen.setPluginData('sceneId', D.id);
section.setPluginData('order', String(D.sectionIndex));
const right = Math.max(...section.children.map((c) => c.x + c.width));
const bottom = Math.max(...section.children.map((c) => c.y + c.height));
section.resizeWithoutConstraints(right + PAD, bottom + PAD);
// Stack the page's sections by their area order.
let y = 0;
const sections = page.children.filter((c) => c.type === 'SECTION').sort((a, b) => +a.getPluginData('order') - +b.getPluginData('order'));
for (const s of sections) { s.x = 0; s.y = y; y += s.height + 200; }
let count = 0;
screen.findAll(() => { count++; return false; });
return { id: screen.id, sceneId: D.id, nodes: count };
