import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { after, test } from "node:test";
import { prepareLiveKitWebrtc } from "./livekit-webrtc-prepare.mjs";
import { sourceHash } from "./openmls-prepare.mjs";

const scratch = await mkdtemp(path.join(os.tmpdir(), "mosh-livekit-webrtc-source-"));
after(() => rm(scratch, { recursive: true, force: true }));

test("the patched libwebrtc bindings can be reconstructed from their offline cache", async () => {
  const cacheDir = path.join(scratch, "cache");
  const online = await prepareLiveKitWebrtc({ destinationRoot: path.join(scratch, "first"), cacheDir });
  const offline = await prepareLiveKitWebrtc({
    destinationRoot: path.join(scratch, "offline with spaces"), cacheDir, offline: true });
  for (const [index, name] of ["webrtc-sys", "libwebrtc"].entries()) {
    const pin = JSON.parse(await readFile(`third_party/${name}-patches/source.json`, "utf8"));
    assert.equal(await sourceHash(online[index]), pin.sourceSha256);
    assert.equal(await sourceHash(offline[index]), pin.sourceSha256);
  }
});
