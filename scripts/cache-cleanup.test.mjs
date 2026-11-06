import assert from "node:assert/strict";
import test from "node:test";
import { staleCaches } from "./cache-cleanup.mjs";

const entry = (id, key, createdAt) => ({ id, key, createdAt });

test("only the newest entry of each key family survives", () => {
  assert.deepEqual(staleCaches([
    entry(1, "cargokit-windows-debug-3131e83f2bcd34f84b9d803cfdd74b4a", "2026-11-01T00:00:00Z"),
    entry(2, "cargokit-windows-debug-29db443fde882bf525683b6733f245f6", "2026-11-06T00:00:00Z"),
    entry(3, "v0-rust-desktop-Windows_NT-x64-fd97a131-626f5aba", "2026-11-01T00:00:00Z"),
    entry(4, "v0-rust-desktop-Windows_NT-x64-b28ac097-3294b904", "2026-11-05T00:00:00Z"),
  ]).sort(), [1, 3]);
});

test("families that differ only before the hashes are kept apart", () => {
  assert.deepEqual(staleCaches([
    entry(1, "cargokit-windows-debug-3131e83f2bcd34f84b9d803cfdd74b4a", "2026-11-01T00:00:00Z"),
    entry(2, "cargokit-windows-release-3131e83f2bcd34f84b9d803cfdd74b4a", "2026-11-06T00:00:00Z"),
    entry(3, "flutter-pub-linux-stable-3.44.8-x64-058e0af2c2b57e369d905a03ac9748b0ebf543c6-b995638776687c22", "2026-11-01T00:00:00Z"),
    entry(4, "flutter-pub-macos-stable-3.44.8-arm64-058e0af2c2b57e369d905a03ac9748b0ebf543c6-b995638776687c22", "2026-11-06T00:00:00Z"),
  ]), []);
});

test("entries saved at the same moment replace neither", () => {
  assert.deepEqual(staleCaches([
    entry(1, "cargokit-windows-debug-3131e83f2bcd34f84b9d803cfdd74b4a", "2026-11-06T00:00:00Z"),
    entry(2, "cargokit-windows-debug-29db443fde882bf525683b6733f245f6", "2026-11-06T00:00:00Z"),
  ]), []);
});
