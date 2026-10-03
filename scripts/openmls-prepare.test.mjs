import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { copyFile, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
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

test("a removed manifest cannot bypass edit protection", async () => {
  const manifest = path.join(destination, "Cargo.toml");
  const original = await readFile(manifest);
  await rm(manifest);
  await assert.rejects(prepareOpenMls({ destination, cacheDir }), /local edits/);
  await assert.rejects(readFile(manifest), { code: "ENOENT" });
  await writeFile(manifest, original);
});

test("a partial source tree is preserved and refused", async () => {
  const partial = path.join(scratch, "partial");
  await mkdir(partial);
  const edited = path.join(partial, "local.rs");
  await writeFile(edited, "local source");
  await assert.rejects(prepareOpenMls({ destination: partial, cacheDir }), /local edits/);
  assert.equal(await readFile(edited, "utf8"), "local source");
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

test("online preparation repairs a damaged archive cache", async () => {
  const archive = path.join(cacheDir, "openmls-0.8.1.crate");
  await writeFile(archive, "interrupted download");
  const repaired = path.join(scratch, "repaired");
  await prepareOpenMls({ destination: repaired, cacheDir });
  assert.equal(await sourceHash(repaired), await sourceHash(destination));
});

test("preparation recovers a lock held by a terminated process", async () => {
  const holder = spawn(process.execPath, ["-e", "setInterval(() => {}, 1000)"], { stdio: "ignore" });
  const exited = once(holder, "exit");
  holder.kill("SIGKILL");
  await exited;
  const claim = path.join(`${destination}.lock`, `${holder.pid}-terminated.json`);
  await writeFile(claim, JSON.stringify({ pid: holder.pid, choosing: true, ticket: 0 }));
  await prepareOpenMls({ destination, cacheDir, offline: true });
  await assert.rejects(readFile(claim), { code: "ENOENT" });
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

test("archive paths with drive-style colons are treated as local files", async () => {
  const driveCache = path.join(scratch, process.platform === "win32" ? "drive-cache" : "D: archive cache");
  await mkdir(driveCache);
  await copyFile(path.join(cacheDir, "openmls-0.8.1.crate"), path.join(driveCache, "openmls-0.8.1.crate"));
  const driveSource = path.join(scratch, "drive-source");
  const originalDirectory = process.cwd();
  try {
    process.chdir(scratch);
    await prepareOpenMls({ destination: driveSource, cacheDir: path.basename(driveCache), offline: true });
  } finally {
    process.chdir(originalDirectory);
  }
  assert.equal(await sourceHash(driveSource), await sourceHash(destination));
});
