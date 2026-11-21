// Compares Figma frames with the Flutter renders they were built from and
// prints the frames that differ most.
import fs from 'node:fs';
import { PNG } from 'pngjs';
import { execute } from './mcp.mjs';

const BG = [17, 19, 21]; // MoshColors.bg1, under the render's transparent pixels

const flatten = (im, i) => {
  const a = im.data[i + 3] / 255;
  return [0, 1, 2].map((c) => im.data[i + c] * a + BG[c] * (1 - a));
};

/** Mean absolute difference (0–255) over 8×8 blocks, so sub-pixel text shifts barely count. */
function score(a, b) {
  const B = 8, w = Math.min(a.width, b.width), h = Math.min(a.height, b.height);
  let total = 0, blocks = 0;
  for (let by = 0; by + B <= h; by += B) for (let bx = 0; bx + B <= w; bx += B) {
    const sa = [0, 0, 0], sb = [0, 0, 0];
    for (let y = by; y < by + B; y++) for (let x = bx; x < bx + B; x++) {
      const pa = flatten(a, (y * a.width + x) * 4), pb = flatten(b, (y * b.width + x) * 4);
      for (let c = 0; c < 3; c++) { sa[c] += pa[c]; sb[c] += pb[c]; }
    }
    total += sa.reduce((s, v, c) => s + Math.abs(v - sb[c]), 0) / (B * B * 3);
    blocks++;
  }
  return total / blocks;
}

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
  scored.sort((a, b) => b.s - a.s);
  console.log(`verified ${scored.length} frames, median difference ${scored[scored.length >> 1]?.s.toFixed(2)}`);
  for (const f of scored.slice(0, top)) console.log(`${f.s.toFixed(2)}  ${f.name}  ${f.id}`);
}
