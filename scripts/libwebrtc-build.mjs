#!/usr/bin/env node
// Builds Google's libwebrtc (LiveKit's webrtc-sdk fork, pinned in
// third_party/libwebrtc-build/build.json) for one target with LiveKit's own
// build scripts, as patched by third_party/webrtc-sys-patches: no H.264.
// CI publishes the archive as a release asset; native builds download it
// (scripts/livekit-webrtc-prepare.mjs) instead of LiveKit's prebuilt.
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { prepareLiveKitWebrtc } from "./livekit-webrtc-prepare.mjs";
import { libwebrtcTarget } from "./support/libwebrtc-targets.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const { values } = parseArgs({ options: {
  target: { type: "string" },
  work: { type: "string", default: path.join(root, ".dart_tool/libwebrtc-build") },
  output: { type: "string", default: path.join(root, "dist") },
} });
if (!values.target) throw new Error("--target <rust triple> is required");
const target = libwebrtcTarget(values.target);
const spec = JSON.parse(await readFile(path.join(root, "third_party/libwebrtc-build/build.json"), "utf8"));
await prepareLiveKitWebrtc();
const scripts = path.join(root, "third_party/webrtc-sys/libwebrtc");
const work = path.resolve(values.work);
await mkdir(work, { recursive: true });
const os = target.script === "macos" ? "mac" : target.script === "windows" ? "win" : target.script;
await writeFile(path.join(work, ".gclient"), `solutions = [
  {
    "name": "src",
    "url": "${spec.repository}@${spec.commit}",
    "custom_deps": {},
    "deps_file": "DEPS",
    "managed": False,
  },
]
target_os = ["${os}"]
`);
const args = ["--arch", target.arch, "--profile", "release"];
if (target.script === "windows") run("cmd", ["/c", path.join(scripts, "build_windows.cmd"), ...args], work);
else run("bash", [path.join(scripts, `build_${target.script}.sh`), ...args], work);
const output = path.resolve(values.output);
await mkdir(output, { recursive: true });
const archive = path.join(output, target.archive);
// Relative: GNU tar on Windows reads "C:" as a remote host.
run("tar", ["-czf", path.relative(work, archive), target.directory], work);
const digest = createHash("sha256").update(await readFile(archive)).digest("hex");
console.log(`${digest}  ${target.archive}`);

function run(command, commandArgs, cwd) {
  const result = spawnSync(command, commandArgs, { cwd, stdio: "inherit", windowsHide: true });
  if (result.status !== 0) throw new Error(`${command} failed (${result.status ?? result.error?.message})`);
}
