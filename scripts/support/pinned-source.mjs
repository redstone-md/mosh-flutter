import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { copyFile, mkdir, mkdtemp, readFile, readdir, rename, rm, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { withSourceLock } from "./source-lock.mjs";

const stampName = ".mosh-source.json";
const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

/** Hash complete source paths and bytes, including upstream tests and notices. */
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

/** Reconstruct a pinned archive and patch without overwriting local source edits. */
export async function preparePinnedSource({ specPath, destination, cacheDir, label, offline = false }) {
  const spec = JSON.parse(await readFile(specPath, "utf8"));
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
        throw new Error(`${label} sources have local edits at ${destination}; save those edits before preparing.`);
      }
    }
    const archive = await loadArchive(spec, cacheDir, label, offline);
    await installSource(spec, archive, destination, path.dirname(specPath), label);
    return destination;
  });
}

async function loadArchive(spec, cacheDir, label, offline) {
  await mkdir(cacheDir, { recursive: true });
  const archive = path.join(cacheDir, spec.archiveName ?? `${spec.name}-${spec.version}.crate`);
  if (await hasFile(archive)) {
    const bytes = await readFile(archive);
    if (sha256(bytes) === spec.archiveSha256) return archive;
    if (offline) throw new Error(`${label} archive checksum mismatch`);
  }
  if (offline) throw new Error(`Offline archive missing: ${archive}`);
  const response = await fetch(spec.url, { signal: AbortSignal.timeout(60_000) });
  if (!response.ok) throw new Error(`Download failed: ${response.status} ${spec.url}`);
  const bytes = Buffer.from(await response.arrayBuffer());
  if (sha256(bytes) !== spec.archiveSha256) throw new Error(`${label} archive checksum mismatch`);
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

async function installSource(spec, archive, destination, patchDir, label) {
  const staging = await mkdtemp(`${destination}.prepare-`);
  const backup = `${staging}.previous`;
  try {
    // GNU tar treats a colon in an archive argument as a remote host on Windows.
    const localArchive = path.join(staging, ".mosh-source.crate");
    await copyFile(archive, localArchive);
    run("tar", ["-xzf", path.basename(localArchive), "--strip-components=1"], staging);
    await rm(localArchive);
    run("git", ["-c", "core.autocrlf=false", "apply", "--no-index", path.join(patchDir, "mosh.patch")], staging);
    if (await sourceHash(staging) !== spec.sourceSha256) {
      throw new Error(`Prepared ${label} sources differ from the verified Mosh source tree`);
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
