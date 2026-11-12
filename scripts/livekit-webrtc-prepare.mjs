#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readFile, rename, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { libwebrtcTarget } from "./support/libwebrtc-targets.mjs";
import { preparePinnedSource } from "./support/pinned-source.mjs";
import { downloadVerified } from "./support/verified-download.mjs";
import { withSourceLock } from "./support/source-lock.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

/** Prepare LiveKit's libwebrtc bindings with Mosh's virtual network. */
export async function prepareLiveKitWebrtc({
  destinationRoot = path.join(root, "third_party"),
  cacheDir = path.join(root, ".dart_tool/native-sources"),
  offline = false,
} = {}) {
  const prepared = [];
  for (const name of ["webrtc-sys", "libwebrtc"]) {
    prepared.push(await preparePinnedSource({
      specPath: path.join(root, "third_party", `${name}-patches`, "source.json"),
      destination: path.join(destinationRoot, name),
      cacheDir,
      label: name,
      offline,
    }));
  }
  return prepared;
}

/**
 * Our libwebrtc build for a Rust target, from the release pinned in
 * third_party/libwebrtc-build/build.json and checked against its SHA-256.
 * `archive` is that build fetched already: Android's comes from Maven Central
 * through Gradle; the others are downloaded from the GitHub release. Returns
 * the directory to pass as LK_CUSTOM_WEBRTC; an LK_CUSTOM_WEBRTC already set
 * (a local build) is returned unchanged.
 */
export async function prepareLibwebrtc(triple, {
  archive,
  cacheDir = path.join(root, ".dart_tool/native-sources"),
  destinationRoot = path.join(root, ".dart_tool/libwebrtc"),
  offline = false,
} = {}) {
  if (process.env.LK_CUSTOM_WEBRTC) return process.env.LK_CUSTOM_WEBRTC;
  const spec = await libwebrtcSpec();
  const target = libwebrtcTarget(triple);
  const sha256 = spec.archives[target.directory];
  if (!sha256) throw new Error(`${spec.release} has no published ${target.archive}; run the libwebrtc workflow`);
  const destination = path.join(destinationRoot, spec.release);
  const prepared = path.join(destination, target.directory);
  const stamp = path.join(prepared, ".mosh-archive");
  await mkdir(destination, { recursive: true });
  return withSourceLock(`${prepared}.lock`, async () => {
    if (await readFile(stamp, "utf8").catch(() => "") === sha256) return prepared;
    const source = archive ?? await releaseArchive(spec, target, { cacheDir, offline });
    if (digest(await readFile(source)) !== sha256) {
      throw new Error(`${source} is not the ${target.archive} pinned for ${spec.release}`);
    }
    const staging = await mkdtemp(path.join(destination, "extract-"));
    try {
      // Relative archive path: GNU tar on Windows reads "C:" as a remote host.
      const result = spawnSync("tar", ["-xzf", path.relative(staging, source)], { cwd: staging, encoding: "utf8" });
      if (result.status !== 0) throw new Error(`tar failed: ${result.error?.message ?? result.stderr}`);
      await writeFile(path.join(staging, target.directory, ".mosh-archive"), sha256);
      await rm(prepared, { recursive: true, force: true });
      await rename(path.join(staging, target.directory), prepared);
    } finally {
      await rm(staging, { recursive: true, force: true });
    }
    return prepared;
  });
}

/** third_party/libwebrtc-build/build.json: the release, its source and archive digests. */
export async function libwebrtcSpec() {
  return JSON.parse(await readFile(path.join(root, "third_party/libwebrtc-build/build.json"), "utf8"));
}

/** The release asset of `target` in the cache, downloaded when missing or corrupt. */
async function releaseArchive(spec, target, { cacheDir, offline }) {
  const sha256 = spec.archives[target.directory];
  await mkdir(cacheDir, { recursive: true });
  const archive = path.join(cacheDir, `${spec.release}-${target.archive}`);
  const bytes = await readFile(archive).catch(() => null);
  if (bytes && digest(bytes) === sha256) return archive;
  if (offline) throw new Error(`Offline archive missing or corrupt: ${archive}`);
  const url = `https://github.com/redstone-md/mosh-flutter/releases/download/${spec.release}/${target.archive}`;
  await writeFile(archive, await downloadVerified(url, sha256));
  return archive;
}

const digest = (bytes) => createHash("sha256").update(bytes).digest("hex");

// `--libwebrtc <rust triple>` also prepares our libwebrtc build for that
// target and prints its directory, for LK_CUSTOM_WEBRTC.
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const offline = process.argv.includes("--offline");
  const triple = process.argv[process.argv.indexOf("--libwebrtc") + 1];
  try {
    await prepareLiveKitWebrtc({ offline });
    if (process.argv.includes("--libwebrtc")) console.log(await prepareLibwebrtc(triple, { offline }));
  } catch (error) {
    console.error(`livekit-webrtc-prepare: ${error.message}`);
    process.exitCode = 1;
  }
}
