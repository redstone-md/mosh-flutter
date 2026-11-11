#!/usr/bin/env node
// Run the packaged capture helper without dumping its binary video output.
import { spawn } from "node:child_process";
import path from "node:path";
import { pathToFileURL } from "node:url";

export function checkCamera(helper, { args = ["--capture"], timeoutMs = 70_000 } = {}) {
  return new Promise((resolve) => {
    const child = spawn(helper, args, { windowsHide: true, stdio: ["pipe", "pipe", "pipe"] });
    let pending = Buffer.alloc(0);
    let ready;
    let stderr = "";
    let result;
    const finish = (value) => {
      if (result) return;
      result = value;
      clearTimeout(timer);
      child.stdin.end();
      child.kill();
    };
    const timer = setTimeout(() => finish({ ok: false, error: "camera startup timed out" }), timeoutMs);
    child.stdin.on("error", () => {});
    child.stderr.on("data", (chunk) => { stderr = (stderr + chunk.toString()).slice(-8192); });
    child.on("error", (error) => finish({ ok: false, error: error.message }));
    child.on("close", (code) => {
      clearTimeout(timer);
      resolve({ ...(result ?? { ok: false, error: "camera exited before delivering a frame" }),
        exitCode: code, ready, stderr: stderr.trim() });
    });
    child.stdout.on("data", (chunk) => {
      if (result) return;
      pending = Buffer.concat([pending, chunk]);
      try {
        if (!ready) {
          const end = pending.indexOf(10);
          if (end < 0 && pending.length <= 8192) return;
          if (end < 0 || end > 8192) throw new Error("invalid camera readiness");
          ready = JSON.parse(pending.subarray(0, end).toString());
          pending = pending.subarray(end + 1);
          if (ready.ready !== true) return; // Wait for stderr and the helper's exit.
        }
        const frame = firstFrame(pending);
        if (frame) finish({ ok: true, ...frame });
      } catch (error) {
        finish({ ok: false, error: error.message });
      }
    });
  });
}

// A frame is `MCP2`, the pixel format's FourCC, big-endian width, height and
// payload length, the capture time in Unix ms, then the packed I420 planes.
function firstFrame(bytes) {
  if (bytes.length < 28) return null;
  const width = bytes.readUInt32BE(8);
  const height = bytes.readUInt32BE(12);
  const size = bytes.readUInt32BE(16);
  if (bytes.toString("ascii", 0, 8) !== "MCP2I420" || width === 0 || height === 0
    || width > 1920 || height > 1920 || width % 2 || height % 2
    || width * height > 1920 * 1080 || size !== width * height * 3 / 2) {
    throw new Error("invalid camera frame");
  }
  if (bytes.length < 28 + size) return null;
  return { width, height, sourceAgeMs: Math.max(0, Date.now() - Number(bytes.readBigUInt64BE(20))) };
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const helper = process.argv[2];
  if (!helper) {
    console.error("Usage: node scripts/native-camera-check.mjs <path-to-mosh-camera-capture.exe> [device-id]");
    process.exitCode = 1;
  } else {
    const args = ["--capture", ...process.argv.slice(3)];
    const result = await checkCamera(path.resolve(helper), { args });
    console.log(JSON.stringify(result, null, 2));
    process.exitCode = result.ok ? 0 : 1;
  }
}
