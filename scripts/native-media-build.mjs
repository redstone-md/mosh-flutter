#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { chmod, copyFile, mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { prepareRingRtc } from "./ringrtc-prepare.mjs";
import { prepareNativeCamera } from "./native-camera-prepare.mjs";
import { nativeProtoc } from "./support/native-protoc.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const { values } = parseArgs({ options: { profile: { type: "string", default: "debug" },
  output: { type: "string" }, targets: { type: "string" }, offline: { type: "boolean", default: false } } });
if (!["debug", "release"].includes(values.profile)) throw new Error("profile must be debug or release");
await prepareRingRtc({ offline: values.offline });
await prepareNativeCamera({ offline: values.offline });
const env = { ...process.env, PROTOC: await nativeProtoc(root) };
const targetRoot = path.join(root, ".dart_tool/native-media/target");
const host = run("rustc", ["-vV"], true).match(/^host: (.+)$/m)?.[1];
if (!host) throw new Error("Cannot determine Rust host target");
const targets = values.targets?.split(",").filter(Boolean) ?? [host];
if (targets.length > 2 || targets.some((target) => !/^[a-zA-Z0-9_-]+$/.test(target))) throw new Error("Invalid native targets");
const output = path.resolve(values.output ?? path.join(root, ".dart_tool/native-media", values.profile));
await mkdir(output, { recursive: true });
const artifacts = [process.platform === "win32" ? "mosh_native_media.dll"
  : process.platform === "darwin" ? "libmosh_native_media.dylib" : "libmosh_native_media.so",
  process.platform === "win32" ? "mosh-camera-capture.exe" : "mosh-camera-capture"];
for (const target of targets) {
  for (const crate of ["engine", "capture"]) {
    run("cargo", ["build", "--locked", "--manifest-path", path.join(root, "mosh-media", crate, "Cargo.toml"),
      "--target-dir", targetRoot, "--target", target, ...(values.profile === "release" ? ["--release"] : [])]);
  }
}
for (const name of artifacts) {
  const sources = targets.map((target) => path.join(targetRoot, target, values.profile, name));
  const destination = path.join(output, name);
  if (sources.length === 2 && process.platform === "darwin") run("lipo", ["-create", ...sources, "-output", destination]);
  else if (sources.length === 1) await copyFile(sources[0], destination);
  else throw new Error("Multiple targets require macOS lipo");
  if (process.platform !== "win32") await chmod(destination, 0o755);
}
const licenses = path.join(output, "licenses");
await mkdir(licenses, { recursive: true });
for (const [source, name] of [["LICENSE", "GPL-3.0.txt"],
  ["third_party/ringrtc/LICENSE", "AGPL-3.0.txt"],
  ["third_party/nokhwa/LICENSE", "Apache-2.0.txt"],
  ["mosh-media/THIRD_PARTY_NOTICES.md", "THIRD_PARTY_NOTICES.md"]]) {
  await copyFile(path.join(root, source), path.join(licenses, name));
}
console.log(`native.media=${output}`);

function run(command, args, capture = false) {
  const result = spawnSync(command, args, { cwd: root, env, encoding: "utf8",
    stdio: capture ? "pipe" : "inherit", windowsHide: true });
  if (result.status !== 0) throw new Error(`${command} failed: ${result.error?.message ?? result.stderr ?? result.status}`);
  return result.stdout;
}
