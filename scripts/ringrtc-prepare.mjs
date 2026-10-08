#!/usr/bin/env node
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { preparePinnedSource } from "./support/pinned-source.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

/** Prepare the isolated RingRTC candidate. This does not enable it in Mosh. */
export async function prepareRingRtc({
  destination = path.join(root, "third_party/ringrtc"),
  cacheDir = path.join(root, ".dart_tool/native-sources"),
  offline = false,
} = {}) {
  return preparePinnedSource({
    specPath: path.join(root, "third_party/ringrtc-patches/source.json"),
    destination,
    cacheDir,
    label: "RingRTC",
    offline,
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try {
    console.log(`ringrtc.source=${await prepareRingRtc({ offline: process.argv.includes("--offline") })}`);
  } catch (error) {
    console.error(`ringrtc-prepare: ${error.message}`);
    process.exitCode = 1;
  }
}
