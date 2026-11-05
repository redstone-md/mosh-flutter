#!/usr/bin/env node
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { preparePinnedSource } from "./support/pinned-source.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

/** Prepare LiveKit's libwebrtc bindings with Mosh's virtual network. */
export async function prepareLiveKitWebrtc({ offline = false } = {}) {
  for (const name of ["webrtc-sys", "libwebrtc"]) {
    await preparePinnedSource({
      specPath: path.join(root, "third_party", `${name}-patches`, "source.json"),
      destination: path.join(root, "third_party", name),
      cacheDir: path.join(root, ".dart_tool/native-sources"),
      label: name,
      offline,
    });
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try {
    await prepareLiveKitWebrtc({ offline: process.argv.includes("--offline") });
  } catch (error) {
    console.error(`livekit-webrtc-prepare: ${error.message}`);
    process.exitCode = 1;
  }
}
