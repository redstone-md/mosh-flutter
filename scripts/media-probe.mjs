#!/usr/bin/env node
/** Two independent Moss installations; test negotiation stays in trusted pipes. */
import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import path from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { setTimeout as delay } from "node:timers/promises";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const { values } = parseArgs({ options: {
  executable: { type: "string", default: path.join(root, "mosh-probe/media-host/target/debug", process.platform === "win32" ? "mosh-media-probe.exe" : "mosh-media-probe") },
  engine: { type: "string", default: path.join(root, "mosh-probe/media/target/debug",
    process.platform === "win32" ? "mosh_media_probe.dll" : process.platform === "darwin" ? "libmosh_media_probe.dylib" : "libmosh_media_probe.so") },
  duration: { type: "string", default: "60" },
  "tamper-key": { type: "boolean", default: false },
} });
const seconds = Number(values.duration);
if (!Number.isFinite(seconds) || seconds < 5 || seconds > 3600) throw new Error("duration must be 5–3600 seconds");

class Worker {
  #process;
  #pending = [];
  #ready;
  #failure;
  #closed;

  constructor(role, mesh) {
    this.#process = spawn(values.executable, [role], { cwd: root,
      env: { ...process.env, MOSH_MEDIA_MESH: mesh, MOSH_MEDIA_ENGINE: path.resolve(values.engine) }, stdio: ["pipe", "pipe", "inherit"] });
    this.#closed = new Promise((resolve) => this.#process.once("close", resolve));
    this.#ready = this.#reply();
    createInterface({ input: this.#process.stdout }).on("line", (line) => {
      if (!line.startsWith("MOSH_MEDIA_JSON ")) return;
      const pending = this.#pending.shift();
      try { pending?.resolve(JSON.parse(line.slice("MOSH_MEDIA_JSON ".length))); }
      catch (error) { pending?.reject(error); }
    });
    this.#process.on("error", (error) => this.#fail(error));
    this.#process.on("close", (code) => this.#fail(new Error(`${role} exited with ${code}`)));
    this.#process.stdin.on("error", (error) => this.#fail(error));
  }

  #fail(error) {
    this.#failure = error;
    for (const pending of this.#pending.splice(0)) pending.reject(error);
  }

  #reply() {
    if (this.#failure) return Promise.reject(this.#failure);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.#fail(new Error("media worker reply timed out")); }, 30_000);
      this.#pending.push({ resolve: (value) => { clearTimeout(timer); resolve(value); },
        reject: (error) => { clearTimeout(timer); reject(error); } });
    });
  }

  async ready() { return this.#ready; }
  async ask(value) {
    const reply = this.#reply();
    this.#process.stdin.write(`${JSON.stringify(value)}\n`);
    return reply;
  }
  async close() {
    if (this.#process.exitCode !== null || this.#process.signalCode !== null) return;
    this.#process.stdin.end(`${JSON.stringify({ action: "stop" })}\n`);
    const ended = await Promise.race([this.#closed.then(() => true), delay(6000).then(() => false)]);
    if (!ended) { this.#process.kill(); await this.#closed; }
  }
}

const mesh = `mosh-media-${randomUUID()}`;
const caller = new Worker("caller", mesh);
const callee = new Worker("callee", mesh);
try {
  const [a, b] = await Promise.all([caller.ready(), callee.ready()]);
  await Promise.all([
    caller.ask({ address: `127.0.0.1:${b.port}`, peer: b.peer }),
    callee.ask({ address: `127.0.0.1:${a.port}`, peer: a.peer }),
  ]);
  const offer = await caller.ask({ action: "offer" });
  if (values["tamper-key"]) offer.key[0] ^= 1;
  await callee.ask({ action: "remote", description: offer });
  const answer = await callee.ask({ action: "answer" });
  await caller.ask({ action: "remote", description: answer });
  await Promise.all([caller.ask({ action: "start" }), callee.ask({ action: "start" })]);
  const started = Date.now();
  let results;
  do {
    await delay(Math.min(5000, seconds * 1000 - (Date.now() - started)));
    results = await Promise.all([caller.ask({ action: "snapshot" }), callee.ask({ action: "snapshot" })]);
    console.log(JSON.stringify({ elapsed_seconds: (Date.now() - started) / 1000,
      caller: results[0], callee: results[1] }));
  } while (Date.now() - started < seconds * 1000);
  const [left, right] = results;
  const ok = values["tamper-key"] ? left.decoded > 0 && right.decoded === 0
    : results.every((result) => result.decoded > 30 && result.audio_received);
  if (!ok) process.exitCode = 1;
  console.log(JSON.stringify({ transport_media_check: ok ? "pass" : "fail",
    tampered_srtp_key: values["tamper-key"],
    host: { platform: process.platform, architecture: process.arch },
    video_source: "synthetic I420", negotiation: "trusted test pipes",
    physical_device_acceptance: "not performed", sustained_720p30: "inspect measurements" }));
} finally {
  await Promise.all([caller.close(), callee.close()]);
}
