#!/usr/bin/env node
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { preparePinnedSource } from "./support/pinned-source.mjs";
export { sourceHash } from "./support/pinned-source.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

/** Materialize the pinned crate and complete Mosh patch. Existing edits are refused. */
export async function prepareOpenMls({
  destination = path.join(root, "third_party/openmls"),
  cacheDir = path.join(root, ".dart_tool/native-sources"),
  offline = false,
} = {}) {
  return preparePinnedSource({
    specPath: path.join(root, "third_party/openmls-patches/source.json"),
    destination,
    cacheDir,
    label: "OpenMLS",
    offline,
  });
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
