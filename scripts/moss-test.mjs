#!/usr/bin/env node
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { createInterface } from "node:readline";
import { pathToFileURL } from "node:url";
import { prepareOpenMls } from "./openmls-prepare.mjs";

// Keep test tools outside application manifests and the working tree.
const trackerVersion = "11.2.3";
const toolsDir = process.env.MOSH_TEST_TOOL_DIR ?? path.join(os.tmpdir(), `mosh-test-tools-${trackerVersion}`);
const trackerDir = path.join(toolsDir, "node_modules", "bittorrent-tracker");
let child;
let interrupted = false;

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.once(signal, () => {
    interrupted = true;
    stopChild(signal);
  });
}

try {
  await prepareOpenMls();
  await ensureTracker();
  if (interrupted) throw new Error("Test run interrupted");
  const { default: Server } = await import(pathToFileURL(path.join(trackerDir, "server.js")));
  const tracker = new Server({
    udp: false, http: true, ws: false, stats: false, trustProxy: false,
    filter: (_infoHash, params, accept) => {
      // Moss's HTTP EventNone is the literal "none". Normalize its regular
      // announces through the server's public hook, without changing Moss.
      if (params.event === "none") params.event = "update";
      accept();
    },
  });
  tracker.on("warning", (error) => console.error(`Moss test tracker: ${error.message}`));
  tracker.on("error", (error) => {
    console.error(`Moss test tracker: ${error.message}`);
    stopChild("SIGTERM");
    process.exitCode = 1;
  });
  try {
    const listening = once(tracker, "listening");
    tracker.listen(0, "127.0.0.1");
    await listening;
    const trackerUrl = `http://127.0.0.1:${tracker.http.address().port}/announce`;
    console.log(`Moss test discovery: ${trackerUrl}`);
    const test = testCommand();
    const voiceUiDataDir = process.argv[2] === "--voice-ui"
      ? await mkdtemp(path.join(os.tmpdir(), "mosh-call-ui-")) : null;
    try {
      const status = await run(test.command, test.args, {
        ...process.env, MOSH_TEST_TRACKER_URL: trackerUrl,
        ...(voiceUiDataDir ? { MOSH_CALL_UI_TEST_DATA_DIR: voiceUiDataDir } : {}),
      });
      process.exitCode = process.exitCode || status;
    } finally {
      // The desktop process has exited, so Windows storage handles are closed.
      if (voiceUiDataDir) await rm(voiceUiDataDir, {
        recursive: true, force: true, maxRetries: 10, retryDelay: 100,
      });
    }
  } finally {
    tracker.http?.closeIdleConnections?.();
    await new Promise((resolve) => tracker.close(resolve));
  }
} catch (error) {
  console.error(`moss-test: ${error.message}`);
  process.exitCode = 1;
}

function testCommand() {
  const args = process.argv.slice(2);
  if (args[0] === "--voice-ui") {
    if (args.length !== 1) throw new Error("--voice-ui does not accept additional arguments");
    const platform = { win32: "windows", darwin: "macos", linux: "linux" }[process.platform];
    if (!platform) throw new Error("Voice UI tests require a desktop host");
    const testArgs = ["drive", "--target", "integration_test/voice_call_test.dart", "--driver", "test_driver/integration.dart", "-d", platform, "--debug", "--no-start-paused"];
    return process.platform === "win32"
      ? { command: "cmd.exe", args: ["/d", "/s", "/c", `flutter ${testArgs.join(" ")}`] }
      : { command: "flutter", args: testArgs };
  }
  if (args[0] === "--native-ui") {
    if (args.length !== 1) throw new Error("--native-ui does not accept additional arguments");
    if (process.platform === "win32") {
      // Flutter's Windows entry point is a batch file. This fixed command
      // passes no caller arguments through cmd; cleanup owns its process tree.
      return { command: "cmd.exe", args: ["/d", "/s", "/c", "flutter test native_test/device_link_test.dart"] };
    }
    return { command: "flutter", args: ["test", "native_test/device_link_test.dart"] };
  }
  return {
    command: process.platform === "win32" ? "cargo.exe" : "cargo",
    args: ["test", "--manifest-path", "mosh-core/Cargo.toml", ...args],
  };
}

async function ensureTracker() {
  try {
    const installed = JSON.parse(await readFile(path.join(trackerDir, "package.json"), "utf8"));
    if (installed.version === trackerVersion) return;
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  const args = ["install", "--prefix", toolsDir, "--no-save", "--no-package-lock", "--omit=dev", "--ignore-scripts", `bittorrent-tracker@${trackerVersion}`];
  // npm.cmd needs a shell on Windows. Run npm's JS entry point with Node.
  const command = process.platform === "win32" ? process.execPath : "npm";
  if (process.platform === "win32") args.unshift(path.join(path.dirname(process.execPath), "node_modules", "npm", "bin", "npm-cli.js"));
  const status = await run(command, args, process.env);
  if (status !== 0) throw new Error(`Tracker tool installation failed with status ${status}`);
}

function run(command, args, env) {
  return new Promise((resolve, reject) => {
    const recording = Boolean(env.MOSH_DEBUG_RECORD_DIR);
    child = spawn(command, args, { stdio: recording ? ["inherit", "pipe", "pipe"] : "inherit", env, shell: false, detached: process.platform !== "win32" });
    if (recording) {
      for (const [input, output] of [[child.stdout, process.stdout], [child.stderr, process.stderr]]) {
        createInterface({ input }).on("line", (line) => {
          output.write(`${line.replace(/([?&]token=)[^&\s]+/g, "$1<REDACTED>")}\n`);
        });
      }
    }
    child.once("error", reject);
    child.once("exit", (status) => {
      child = undefined;
      resolve(status ?? 1);
    });
  });
}

function stopChild(signal) {
  if (!child?.pid) return;
  if (process.platform === "win32") {
    const killer = spawn("taskkill.exe", ["/PID", String(child.pid), "/T", "/F"], { stdio: "ignore", shell: false });
    killer.once("error", (error) => console.error(`moss-test cleanup: ${error.message}`));
  } else {
    try {
      process.kill(-child.pid, signal);
    } catch (error) {
      if (error.code !== "ESRCH") throw error;
    }
  }
}
