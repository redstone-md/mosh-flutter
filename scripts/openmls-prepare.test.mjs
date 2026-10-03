import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { after, test } from "node:test";
import { prepareOpenMls, sourceHash } from "./openmls-prepare.mjs";

const scratch = await mkdtemp(path.join(os.tmpdir(), "mosh-openmls-test-"));
const destination = path.join(scratch, "source with spaces");
const cacheDir = path.join(scratch, "cache");
after(() => rm(scratch, { recursive: true, force: true }));

test("complete patch reproduces the committed source bytes and works offline", async () => {
  await prepareOpenMls({ destination, cacheDir });
  const expected = JSON.parse(await readFile("third_party/openmls-patches/source.json", "utf8"));
  assert.equal(await sourceHash(destination), expected.sourceSha256);
  await Promise.all([
    prepareOpenMls({ destination, cacheDir, offline: true }),
    prepareOpenMls({ destination, cacheDir, offline: true }),
  ]);
  assert.equal(await sourceHash(destination), expected.sourceSha256);
});

test("existing source edits are preserved and refused", async () => {
  const edited = path.join(destination, "Cargo.toml");
  const original = await readFile(edited, "utf8");
  await writeFile(edited, `${original}\n# local edit\n`);
  await assert.rejects(prepareOpenMls({ destination, cacheDir }), /local edits/);
  assert.equal(await readFile(edited, "utf8"), `${original}\n# local edit\n`);
  await writeFile(edited, original);
});

test("a damaged cached archive cannot materialize source", async () => {
  const archive = path.join(cacheDir, "openmls-0.8.1.crate");
  const bytes = await readFile(archive);
  await writeFile(archive, "tampered archive");
  await assert.rejects(
    prepareOpenMls({ destination: path.join(scratch, "tampered"), cacheDir, offline: true }),
    /checksum mismatch/,
  );
  await writeFile(archive, bytes);
});

test("offline preparation from a cached archive recreates the full source", async () => {
  const second = path.join(scratch, "offline");
  await prepareOpenMls({ destination: second, cacheDir, offline: true });
  assert.equal(await sourceHash(second), await sourceHash(destination));
});

test("offline preparation without a cached archive fails clearly", async () => {
  await assert.rejects(
    prepareOpenMls({ destination: path.join(scratch, "absent"), cacheDir: path.join(scratch, "empty"), offline: true }),
    /Offline archive missing/,
  );
});
