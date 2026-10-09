import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { after, test } from "node:test";
import { prepareRingRtc } from "./ringrtc-prepare.mjs";
import { sourceHash } from "./openmls-prepare.mjs";

const scratch = await mkdtemp(path.join(os.tmpdir(), "mosh-ringrtc-source-"));
after(() => rm(scratch, { recursive: true, force: true }));

test("the pinned media probe source can be reconstructed from its offline cache", async () => {
  const cacheDir = path.join(scratch, "cache");
  const original = await prepareRingRtc({ destination: path.join(scratch, "first"), cacheDir });
  const offline = await prepareRingRtc({ destination: path.join(scratch, "offline with spaces"), cacheDir, offline: true });
  const pin = JSON.parse(await readFile("third_party/ringrtc-patches/source.json", "utf8"));
  assert.equal(await sourceHash(original), pin.sourceSha256);
  assert.equal(await sourceHash(offline), pin.sourceSha256);
});
