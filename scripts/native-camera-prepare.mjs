import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { preparePinnedSource } from "./support/pinned-source.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

export async function prepareNativeCamera({ offline = false } = {}) {
  for (const [destination, patches] of [["nokhwa", "nokhwa-patches"],
    ["nokhwa-macos", "nokhwa-macos-patches"]]) {
    await preparePinnedSource({ specPath: path.join(root, "third_party", patches, "source.json"),
      destination: path.join(root, "third_party", destination),
      cacheDir: path.join(root, ".dart_tool/native-sources"), label: destination, offline });
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  await prepareNativeCamera({ offline: process.argv.includes("--offline") });
}
