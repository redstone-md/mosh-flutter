// Compares Figma frames with the Flutter renders they were built from and
// prints the frames that differ most.
import fs from 'node:fs';
import { PNG } from 'pngjs';
import { execute } from './mcp.mjs';
import { windowColor } from './tokens.mjs';

const BG = windowColor().map((v) => v * 255); // under the render's transparent pixels

const flatten = (im, i) => {
  const a = im.data[i + 3] / 255;
  return [0, 1, 2].map((c) => im.data[i + c] * a + BG[c] * (1 - a));
};

/** Mean absolute difference (0–255) over 8×8 blocks, so sub-pixel text shifts barely count.
 * Edge blocks may be smaller; frames of different size score the maximum. */
function score(a, b) {
  if (a.width !== b.width || a.height !== b.height) return 255;
  const B = 8;
  let total = 0, blocks = 0;
  for (let by = 0; by < a.height; by += B) for (let bx = 0; bx < a.width; bx += B) {
    const sa = [0, 0, 0], sb = [0, 0, 0];
    const ey = Math.min(by + B, a.height), ex = Math.min(bx + B, a.width);
    for (let y = by; y < ey; y++) for (let x = bx; x < ex; x++) {
      const pa = flatten(a, (y * a.width + x) * 4), pb = flatten(b, (y * b.width + x) * 4);
      for (let c = 0; c < 3; c++) { sa[c] += pa[c]; sb[c] += pb[c]; }
    }
    const n = (ey - by) * (ex - bx) * 3;
    total += sa.reduce((s, v, c) => s + Math.abs(v - sb[c]), 0) / n;
    blocks++;
  }
  return total / blocks;
}

const median = (values) => {
  const s = [...values].sort((x, y) => x - y), mid = s.length >> 1;
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
};

// Plugin code that exports frame [id] at scale 1 as base64 PNG.
const exportCode = (id) => [
  `const node = await figma.getNodeByIdAsync(${JSON.stringify(id)});`,
  "const png = await node.exportAsync({ format: 'PNG', constraint: { type: 'SCALE', value: 1 } });",
  'return figma.base64Encode(png);',
].join('\n');

/** [frames]: { id, ref, name }. Prints the median and the worst [top] frames. */
export async function verify(frames, top = 15) {
  const scored = [];
  for (const f of frames) {
    const b64 = await execute(exportCode(f.id), 60000);
    const s = score(PNG.sync.read(Buffer.from(b64, 'base64')), PNG.sync.read(fs.readFileSync(f.ref)));
    scored.push({ ...f, s });
  }
  if (!scored.length) return;
  scored.sort((a, b) => b.s - a.s);
  console.log(`verified ${scored.length} frames, median difference ${median(scored.map((f) => f.s)).toFixed(2)}`);
  for (const f of scored.slice(0, top)) console.log(`${f.s.toFixed(2)}  ${f.name}  ${f.id}`);
}
