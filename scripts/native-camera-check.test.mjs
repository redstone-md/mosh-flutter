import assert from "node:assert/strict";
import test from "node:test";
import { checkCamera } from "./native-camera-check.mjs";

const check = (source, timeoutMs = 1000) => checkCamera(process.execPath,
  { args: ["-e", source], timeoutMs });
const frame = `const frame = Buffer.alloc(28);
  frame.write('MCP1');
  frame.writeUInt32BE(1, 4); frame.writeUInt32BE(1, 8); frame.writeUInt32BE(4, 12);
  frame.writeBigUInt64BE(BigInt(Date.now()), 16);`;
const keepAlive = "process.stdin.resume();";

test("reads readiness and a complete frame across pipe chunks without exposing pixels", async () => {
  const result = await check(`${frame}
    console.log('{"ready":true}');
    process.stdout.write(frame.subarray(0, 10));
    setTimeout(() => process.stdout.write(frame.subarray(10)), 20);
    ${keepAlive}`);
  assert.equal(result.ok, true);
  assert.equal(result.width, 1);
  assert.equal(result.height, 1);
  assert.ok(result.sourceAgeMs < 1000);
  assert.equal("pixels" in result, false);
});

test("retains a driver error emitted after failed readiness", async () => {
  const result = await check(`console.log('{"error":"camera_unavailable"}');
    console.error('camera capture: permission denied'); process.exitCode = 1;`);
  assert.equal(result.ok, false);
  assert.equal(result.ready.error, "camera_unavailable");
  assert.equal(result.stderr, "camera capture: permission denied");
  assert.equal(result.exitCode, 1);
});

test("rejects malformed and oversized output and kills stalled helpers", async () => {
  for (const output of ["not json\n", "x".repeat(8193), '{"ready":true}\n' + "x".repeat(24)]) {
    const result = await check(`process.stdout.write(${JSON.stringify(output)}); ${keepAlive}`);
    assert.equal(result.ok, false);
    assert.match(result.error, /JSON|invalid camera/);
  }
  const stalled = await check(keepAlive, 50);
  assert.equal(stalled.ok, false);
  assert.equal(stalled.error, "camera startup timed out");
});

test("reports a missing helper without hanging", async () => {
  const result = await checkCamera("/missing-mosh-camera-helper");
  assert.equal(result.ok, false);
  assert.match(result.error, /ENOENT/);
});
