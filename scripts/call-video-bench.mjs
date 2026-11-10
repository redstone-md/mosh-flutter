#!/usr/bin/env node
// Measures what one call video frame costs on this machine and prints a
// Markdown table: ms per frame and the share of one core at 30 fps, for
// 640x360, 1280x720 and 1920x1080. The parts are
// mosh-core/src/native_call/benchmark.rs and benchmark/*.dart.
//
//   node scripts/call-video-bench.mjs [--output report.md]
//
// MOSH_MEDIA_ENGINE names a built engine library; without it the release
// engine is built first.
import { spawnSync } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { parseArgs } from "node:util";
import { engineLibrary } from "./support/native-media-artifacts.mjs";

const SIZES = ["640x360", "1280x720", "1920x1080"];
const MARK = "call-video-bench ";

/** The measurements ({ case, width, height, ms }) among a part's output lines. */
export function rows(output) {
  return output.split(/\r?\n/).filter((line) => line.startsWith(MARK))
    .map((line) => JSON.parse(line.slice(MARK.length)));
}

/** One table line per case, in the order the cases first ran. */
export function table(measured) {
  const cases = new Map();
  for (const { case: name, width, height, ms } of measured) {
    if (!cases.has(name)) cases.set(name, {});
    // At 30 fps a frame of `ms` takes ms * 30 / 1000 of a core.
    cases.get(name)[`${width}x${height}`] = `${ms.toFixed(ms < 10 ? 2 : 1)} (${Math.round(ms * 3)}%)`;
  }
  return [`| Case | ${SIZES.join(" | ")} |`, "|------|---------|----------|-----------|",
    ...[...cases].map(([name, cells]) => `| ${name} | ${SIZES.map((size) => cells[size] ?? "").join(" | ")} |`),
  ].join("\n");
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
  const { values } = parseArgs({ options: { output: { type: "string" } } });
  const run = (command, args, env = process.env) => {
    const result = spawnSync(command, args, { cwd: root, env, encoding: "utf8", maxBuffer: 64 * 1024 * 1024,
      stdio: ["ignore", "pipe", "inherit"], shell: process.platform === "win32", windowsHide: true });
    if (result.status !== 0) throw new Error(`${command} ${args.join(" ")} failed:\n${result.stdout ?? result.error}`);
    return result.stdout;
  };
  const engine = process.env.MOSH_MEDIA_ENGINE || (() => {
    run("node", ["scripts/native-media-build.mjs", "--profile", "release"]);
    return path.join(root, ".dart_tool/native-media/release", engineLibrary);
  })();
  const scratch = path.join(root, ".dart_tool/call-video-bench");
  await mkdir(scratch, { recursive: true });
  const transport = path.join(scratch, process.platform === "win32" ? "call_frame_transport.exe" : "call_frame_transport");
  run("dart", ["compile", "exe", "benchmark/call_frame_transport.dart", "-o", transport]);
  const measured = [
    run("cargo", ["test", "--release", "--manifest-path", "mosh-core/Cargo.toml", "--lib", "--features", "call-video-bench",
      "native_call::benchmark", "--", "--ignored", "--nocapture"], { ...process.env, MOSH_MEDIA_ENGINE: engine }),
    run(transport, []),
    run("flutter", ["test", "benchmark/call_video_decode.dart"]),
  ].map((output) => {
    // A part that printed nothing, or lost a size, must not leave a quiet gap.
    const part = rows(output);
    if (part.length === 0 || part.length % SIZES.length !== 0) throw new Error(`incomplete measurements:\n${output}`);
    return part;
  }).flat();
  const report = [
    `Call video frame path on ${os.type()} ${os.release()} ${os.arch()}, ${os.cpus()[0]?.model ?? "unknown CPU"}.`,
    "Median ms per frame of 60 runs after 5 warm-ups; in brackets the share of one core at 30 fps.",
    "", table(measured), "",
  ].join("\n");
  if (values.output) await writeFile(path.resolve(values.output), report);
  console.log(report);
}
