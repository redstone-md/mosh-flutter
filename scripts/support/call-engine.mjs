// The call engine a build packages (MOSH_CALL_ENGINE). Both export the same
// mosh_media_* ABI under the same library name; RingRTC stays the default
// until the libwebrtc engine replaces it (MOSH-76).
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { prepareLibwebrtc, prepareLiveKitWebrtc } from "../livekit-webrtc-prepare.mjs";
import { prepareRingRtc } from "../ringrtc-prepare.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

const engines = {
  ringrtc: {
    crate: "engine",
    targetDirectory: "target",
    async prepare({ offline }) {
      if (process.platform === "darwin"
          && spawnSync("realpath", ["-e", "."]).status !== 0
          && spawnSync("grealpath", ["."]).status !== 0) {
        throw new Error("RingRTC needs GNU realpath on macOS: brew install coreutils");
      }
      await prepareRingRtc({ offline });
    },
    async targetEnv() {
      return {};
    },
    async licenses() {
      return [[path.join(root, "third_party/ringrtc/LICENSE"), "AGPL-3.0.txt"]];
    },
  },
  webrtc: {
    crate: "webrtc",
    targetDirectory: "target-webrtc",
    async prepare({ offline }) {
      await prepareLiveKitWebrtc({ offline });
    },
    /** Points webrtc-sys at our libwebrtc build for `triple`. */
    async targetEnv(triple, { offline }) {
      if (triple.includes("linux-gnu") && !process.env.CXX?.includes("clang")) {
        throw new Error("libwebrtc's hermetic libc++ needs clang 21 or later: set CC and CXX to it");
      }
      return { LK_CUSTOM_WEBRTC: await prepareLibwebrtc(triple, { offline }) };
    },
    async licenses(triple, { offline }) {
      return [[path.join(await prepareLibwebrtc(triple, { offline }), "LICENSE.md"), "WEBRTC-LICENSE.md"]];
    },
  },
};

/** The engine named `name`: `ringrtc` or `webrtc`. */
export function callEngine(name) {
  const engine = engines[name];
  if (!engine) throw new Error(`Unknown call engine "${name}": use ringrtc or webrtc`);
  return engine;
}
