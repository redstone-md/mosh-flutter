#!/usr/bin/env node
// Exercise the production JNI entry point with a real JVM, without a phone.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const probe = path.join(root, "mosh-probe/android-context");
const output = path.join(root, ".dart_tool/android-context");
const classes = path.join(output, "classes");
await mkdir(classes, { recursive: true });
run("cargo", ["build", "--locked", "--manifest-path", path.join(probe, "Cargo.toml"),
  "--target-dir", output]);
run("javac", ["-d", classes, path.join(probe, "MoshNative.java")]);
const library = process.platform === "win32" ? "mosh_android_context_probe.dll"
  : process.platform === "darwin" ? "libmosh_android_context_probe.dylib"
    : "libmosh_android_context_probe.so";
const args = ["-cp", classes, "app.mosh.mosh.MoshNative", path.join(output, "debug", library)];
const missing = spawnSync("java", [...args, "without-bootstrap"], { cwd: root, encoding: "utf8" });
assert.notEqual(missing.status, 0, "the probe must reproduce an uninitialized audio context");
assert.match(missing.stderr, /native audio context is missing/);
console.log("Before bootstrap: native audio context is missing (reproduced).");
run("java", args);
run("javac", ["-d", classes, path.join(probe, "AudioPolicyProbe.java"),
  path.join(root, "android/app/src/main/java/app/mosh/mosh/MoshCallAudioPolicy.java")]);
run("java", ["-cp", classes, "app.mosh.mosh.AudioPolicyProbe"]);
run("javac", ["-d", classes, path.join(probe, "AccessPolicyProbe.java"),
  path.join(root, "android/app/src/main/java/app/mosh/mosh/MoshAccessPolicy.java")]);
run("java", ["-cp", classes, "app.mosh.mosh.AccessPolicyProbe"]);
run("javac", ["-d", classes, path.join(probe, "WaitingPolicyProbe.java"),
  path.join(root, "android/app/src/main/java/app/mosh/mosh/MoshWaitingExecution.java"),
  path.join(root, "android/app/src/main/java/app/mosh/mosh/MoshCallActions.java"),
  path.join(root, "android/app/src/main/java/app/mosh/mosh/MoshWaitingPolicy.java")]);
run("java", ["-cp", classes, "app.mosh.mosh.WaitingPolicyProbe"]);

function run(command, args) {
  const result = spawnSync(command, args, { cwd: root, stdio: "inherit", windowsHide: true });
  if (result.status !== 0) throw new Error(`${command} failed: ${result.error?.message ?? result.status}`);
}
