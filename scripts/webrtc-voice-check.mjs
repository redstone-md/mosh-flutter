#!/usr/bin/env node
// A voice call over two real Moss nodes with the engine given as argument,
// measured by mosh-probe/media-bench: each peer gets its own PulseAudio
// server whose null sinks are its microphone and speaker, a 1 kHz burst goes
// into the caller's microphone every second, and the callee must hear them.
// Linux only (PulseAudio); CI runs it for the libwebrtc engine.
import { spawnSync } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const engine = path.resolve(process.argv[2] ?? "");
const seconds = 15;
const pulse = "/tmp/mosh-pa";

await mkdir(pulse, { recursive: true });
for (const side of ["a", "b"]) {
  await writeFile(path.join(pulse, `${side}.pa`), [
    `load-module module-native-protocol-unix socket=${pulse}/${side}.sock auth-anonymous=1`,
    "load-module module-null-sink sink_name=mic rate=48000 channels=1",
    "load-module module-null-sink sink_name=spk rate=48000 channels=1",
    "set-default-sink spk",
    "set-default-source mic.monitor",
    "",
  ].join("\n"));
  const runtime = path.join(pulse, `rt-${side}`);
  await mkdir(runtime, { recursive: true });
  run("pulseaudio", ["-n", "-F", path.join(pulse, `${side}.pa`), "--daemonize=yes", "--exit-idle-time=-1"],
    { XDG_RUNTIME_DIR: runtime, HOME: runtime, DBUS_SESSION_BUS_ADDRESS: "disabled:" });
}
const bench = path.join(root, "mosh-probe/media-bench");
run("cargo", ["build", "--locked", "--release", "--manifest-path", path.join(bench, "Cargo.toml")]);
const output = run(path.join(bench, "target/release/mosh-media-bench"),
  ["run", "--moss", "--engine", engine, "--seconds", String(seconds)]);
const result = JSON.parse(output.trim().split("\n").at(-1));
console.log(JSON.stringify(result, null, 2));
// One burst may straddle the start or the end of the window.
if (result.bursts_heard < seconds - 2) throw new Error(`callee heard ${result.bursts_heard} of ${seconds} bursts`);
if (!(result.mouth_to_ear_ms < 300)) throw new Error(`mouth-to-ear ${result.mouth_to_ear_ms} ms`);

function run(command, args, env = {}) {
  const result = spawnSync(command, args, { cwd: root, env: { ...process.env, ...env }, encoding: "utf8",
    stdio: ["ignore", "pipe", "inherit"] });
  if (result.status !== 0) throw new Error(`${command} failed (${result.status ?? result.error?.message})`);
  return result.stdout;
}
