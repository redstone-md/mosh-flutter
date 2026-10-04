#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { copyFile, mkdir, mkdtemp, readFile, readdir, rename, rm, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { withSourceLock } from "./support/source-lock.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const patchDir = path.join(root, "third_party/openmls-patches");
const stampName = ".mosh-source.json";
const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

/** Hash paths and bytes, including upstream tests and license notices. */
export async function sourceHash(directory) {
  const files = [];
  async function visit(relative) {
    for (const entry of await readdir(path.join(directory, relative), { withFileTypes: true })) {
      const name = path.posix.join(relative, entry.name);
      if (name === stampName || name === "target") continue;
      if (entry.isDirectory()) await visit(name);
      else if (entry.isFile()) files.push(name);
      else throw new Error(`Unexpected source entry: ${name}`);
    }
  }
  await visit("");
  const digest = createHash("sha256");
  for (const name of files.sort()) {
    digest.update(`${name}\0${sha256(await readFile(path.join(directory, name)))}\n`);
  }
  return digest.digest("hex");
}

/** Materialize the pinned crate and complete Mosh patch. Existing edits are refused. */
export async function prepareOpenMls({
  destination = path.join(root, "third_party/openmls"),
  cacheDir = path.join(root, ".dart_tool/native-sources"),
  offline = false,
} = {}) {
  const spec = JSON.parse(await readFile(path.join(patchDir, "source.json"), "utf8"));
  await mkdir(path.dirname(destination), { recursive: true });
  return withSourceLock(`${destination}.lock`, async () => {
    if (await hasFile(destination)) {
      const actual = await sourceHash(destination);
      if (actual === spec.sourceSha256) {
        await writeFile(path.join(destination, stampName), `${JSON.stringify(spec)}\n`);
        return destination;
      }
      const stamp = await readStamp(destination);
      if (stamp?.sourceSha256 !== actual) {
        throw new Error(`OpenMLS sources have local edits at ${destination}; save those edits before preparing.`);
      }
    }
    const archive = await loadArchive(spec, cacheDir, offline);
    await installSource(spec, archive, destination);
    return destination;
  });
}

async function loadArchive(spec, cacheDir, offline) {
  await mkdir(cacheDir, { recursive: true });
  const archive = path.join(cacheDir, `${spec.name}-${spec.version}.crate`);
  if (await hasFile(archive)) {
    const bytes = await readFile(archive);
    if (sha256(bytes) === spec.archiveSha256) return archive;
    if (offline) throw new Error("OpenMLS archive checksum mismatch");
  }
  if (offline) throw new Error(`Offline archive missing: ${archive}`);
  const response = await fetch(spec.url, { signal: AbortSignal.timeout(60_000) });
  if (!response.ok) throw new Error(`Download failed: ${response.status} ${spec.url}`);
  const bytes = Buffer.from(await response.arrayBuffer());
  verifyArchive(bytes, spec.archiveSha256);
  const staging = await mkdtemp(path.join(cacheDir, "archive-"));
  try {
    const downloaded = path.join(staging, "source.crate");
    await writeFile(downloaded, bytes);
    await rename(downloaded, archive);
  } finally {
    await rm(staging, { recursive: true, force: true });
  }
  return archive;
}

function verifyArchive(bytes, expected) {
  if (sha256(bytes) !== expected) throw new Error("OpenMLS archive checksum mismatch");
}

async function installSource(spec, archive, destination) {
  const staging = await mkdtemp(`${destination}.prepare-`);
  const backup = `${staging}.previous`;
  try {
    // GNU tar treats a colon in an archive argument as a remote host (Windows drives).
    const localArchive = path.join(staging, ".mosh-source.crate");
    await copyFile(archive, localArchive);
    run("tar", ["-xzf", path.basename(localArchive), "--strip-components=1"], staging);
    await rm(localArchive);
    run("git", ["-c", "core.autocrlf=false", "apply", "--no-index", path.join(patchDir, "mosh.patch")], staging);
    if (await sourceHash(staging) !== spec.sourceSha256) {
      throw new Error("Prepared OpenMLS sources differ from the verified Mosh source tree");
    }
    await writeFile(path.join(staging, stampName), `${JSON.stringify(spec)}\n`);
    if (await hasFile(destination)) await rename(destination, backup);
    try {
      await rename(staging, destination);
    } catch (error) {
      if (await hasFile(backup)) await rename(backup, destination);
      throw error;
    }
    await rm(backup, { recursive: true, force: true });
  } finally {
    await rm(staging, { recursive: true, force: true });
  }
}

function run(command, args, cwd) {
  const result = spawnSync(command, args, { cwd, encoding: "utf8" });
  if (result.status !== 0) throw new Error(`${command} failed: ${result.error?.message ?? result.stderr}`);
}

async function hasFile(name) {
  try {
    await stat(name);
    return true;
  } catch (error) {
    if (error.code === "ENOENT") return false;
    throw error;
  }
}

async function readStamp(destination) {
  try {
    return JSON.parse(await readFile(path.join(destination, stampName), "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try {
    const destination = await prepareOpenMls({ offline: process.argv.includes("--offline") });
    console.log(`openmls.source=${destination}`);
  } catch (error) {
    console.error(`openmls-prepare: ${error.message}`);
    process.exitCode = 1;
  }
}
