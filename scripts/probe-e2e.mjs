#!/usr/bin/env node
// Runs a real two-ended conversation between this machine and a remote host,
// and prints one merged timeline. The remote end is driven over SSH, so a full
// round trip costs one command instead of two humans with screenshots.
//
//   node scripts/probe-e2e.mjs --host <user>@<relay-host>
//   node scripts/probe-e2e.mjs --host <user>@<relay-host> --kind group
//   node scripts/probe-e2e.mjs --host <user>@<relay-host> --kind channel
//
// Exit code is the verdict: 0 when the message got through, 1 otherwise. Only
// a DM acks, so only a DM can be judged from the dialing end; a group and a
// channel are judged by the listening end, whose exit code counts too.
import { spawn } from "node:child_process";
import { writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const DEFAULT_REMOTE_BIN = "/usr/local/bin/mosh-probe";

// Everything the overlay exists for only matters between two hosts that cannot
// be dialed. A public relay on one end is the easy case and hides it, so the
// remote half can be wrapped in anything that ends up invoking the probe —
// notably a container on the default bridge, which is a real NAT rather than a
// simulated one:
//
//   --remote-bin "docker run --rm -v /usr/local/bin:/opt/probe:ro \
//                 debian:bookworm-slim /opt/probe/mosh-probe"
const REMOTE_BIN = arg("remote-bin", DEFAULT_REMOTE_BIN);
// The moss debug plane is the field-forensics seam (session-close reasons in a
// .mossrec NDJSON). The local half inherits this env from the runner's own
// environment; the remote half cannot, so the flag below ships the variable
// inside the SSH command string.
const REMOTE_DEBUG_DIR = arg("remote-debug-dir");
const remoteDebugEnv = REMOTE_DEBUG_DIR ? `MOSH_DEBUG_RECORD_DIR=${REMOTE_DEBUG_DIR} ` : "";
const LOCAL_BIN = path.resolve(
  "mosh-probe",
  "target",
  "release",
  process.platform === "win32" ? "mosh-probe.exe" : "mosh-probe",
);

function arg(name, fallback = null) {
  const hit = process.argv.indexOf(`--${name}`);
  return hit === -1 ? fallback : process.argv[hit + 1];
}

const HOST = arg("host");
const TIMEOUT = arg("timeout", "180");
const BIND = arg("bind-interface");
const MESSAGE = arg("message", "probe ping");
// More than one means the real test: N conversations open at the same time from
// a single local process, against N independent remote counterparts.
const SESSIONS = Number(arg("sessions", "1"));
// Which conversation kind the run drives. `--sessions N` is a DM-only shape.
const KIND = arg("kind", "dm");
// A channel has no invite: both ends have to be told the same name. A fresh
// one per run keeps two runs from reading each other's traffic.
const CHANNEL = arg("channel", `probe-${Date.now().toString(36)}`);

if (!HOST) {
  console.error(
    "usage: probe-e2e.mjs --host user@host [--kind dm|group|channel] [--timeout 180]" +
      " [--channel NAME] [--bind-interface NAME]",
  );
  process.exit(2);
}

if (!["dm", "group", "channel"].includes(KIND)) {
  console.error(`unknown --kind ${KIND} (expected dm, group or channel)`);
  process.exit(2);
}

const events = [];

/// Adds one complete JSONL line to the merged timeline. `run` has already
/// reassembled chunk boundaries, so anything unparseable here is a real
/// anomaly and gets surfaced rather than dropped.
function collect(source, line) {
  const text = line.trim();
  if (!text.startsWith("{")) return;
  try {
    events.push({ source, ...JSON.parse(text) });
  } catch (error) {
    process.stderr.write(`[${source}] unparseable line (${error.message}): ${text.slice(0, 160)}\n`);
  }
}

function run(command, args, source, onEvent) {
  const child = spawn(command, args, { stdio: ["ignore", "pipe", "pipe"] });
  let pending = "";
  child.stdout.on("data", (chunk) => {
    pending += chunk.toString();
    const lines = pending.split("\n");
    pending = lines.pop() ?? "";
    for (const line of lines) {
      collect(source, line);
      if (onEvent) onEvent(events.at(-1));
    }
  });
  child.stderr.on("data", (chunk) => process.stderr.write(`[${source}] ${chunk}`));
  return child;
}

/** Resolves once the given remote source prints its invite, or rejects if it dies first. */
function waitForInvite(remote, source = "remote") {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`${source} never emitted an invite`)), 60_000);
    const check = setInterval(() => {
      const hit = events.find((e) => e.source === source && e.kind === "invite");
      if (hit) {
        clearInterval(check);
        clearTimeout(timer);
        resolve(hit.data.invite_uri);
      } else if (remote.exitCode !== null) {
        clearInterval(check);
        clearTimeout(timer);
        reject(new Error(`remote exited early (${remote.exitCode})`));
      }
    }, 200);
  });
}

/** Resolves once the remote has printed `count` invites, or rejects if it dies. */
function waitForInvites(remote, count) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error(`remote emitted fewer than ${count} invites`)),
      90_000,
    );
    const check = setInterval(() => {
      const hits = events.filter((e) => e.source === "remote" && e.kind === "invite");
      if (hits.length >= count) {
        clearInterval(check);
        clearTimeout(timer);
        resolve(hits.slice(0, count).map((hit) => hit.data.invite_uri));
      } else if (remote.exitCode !== null) {
        clearInterval(check);
        clearTimeout(timer);
        reject(new Error(`remote exited early (${remote.exitCode})`));
      }
    }, 200);
  });
}

function describe(label, snap) {
  if (!snap) return `${label}: no snapshot`;
  const m = snap.data.mesh ?? {};
  return [
    `${label}: state=${snap.data.state} transport=${snap.data.transport}`,
    `nat=${m.nat_type} advertised=${m.advertised_addr}`,
    `peers=${m.peer_count} relay_capable=${m.relay_capable_peer_count} known=${m.known_peer_count}`,
  ].join("  ");
}

async function report(code) {
  events.sort((a, b) => a.ts - b.ts);
  await writeFile("probe-timeline.jsonl", events.map((e) => JSON.stringify(e)).join("\n"));

  const flags = new Set(
    events.filter((e) => e.kind === "verdict").flatMap((v) => v.data.flags ?? []),
  );
  const last = (source) =>
    [...events].reverse().find((e) => e.source === source && e.kind === "snapshot");

  console.error("");
  console.error(describe("local ", last("local")));
  // Multi-session runs label each counterpart separately, so there is no single
  // "remote" to print — report every one of them instead of nothing.
  const remoteSources = [...new Set(events.map((e) => e.source))]
    .filter((source) => source.startsWith("remote"))
    .sort();
  for (const source of remoteSources) console.error(describe(source, last(source)));
  if (flags.size) console.error(`flags: ${[...flags].join(", ")}`);
  console.error(`timeline: probe-timeline.jsonl (${events.length} events)`);
  // A DM is judged delivered (the peer acked); a group and a channel are
  // judged received (the far end read the body).
  const passed = KIND === "dm" ? "delivered" : "received";
  console.error(code === 0 ? `VERDICT: ${passed}` : "VERDICT: failed");
}

/// Several conversations at once, all from ONE local process — the shape the
/// desktop app has and a single dial does not. Each remote `listen` is its own
/// process and therefore its own counterpart, so N of them stand in for N
/// different people without needing N people.
async function runMany(sessions, bindArgs) {
  // ONE remote process serving every conversation, not one per conversation.
  // N processes on a single host would put N nodes behind one address — the
  // exact shape this work removed — so the far end would be reproducing the
  // defect the run is trying to measure.
  const listenCmd = [
    `${remoteDebugEnv}${REMOTE_BIN}`,
    "listen-many",
    "--sessions",
    String(sessions),
    "--timeout-secs",
    TIMEOUT,
  ].join(" ");
  const remote = run("ssh", ["-o", "BatchMode=yes", HOST, listenCmd], "remote");
  const remotes = [remote];
  const invites = await waitForInvites(remote, sessions);
  console.error(`[runner] ${invites.length} invites received, dialing all from one process`);

  const dialArgs = ["dial-many"];
  for (const invite of invites) dialArgs.push("--invite", invite);
  dialArgs.push("--message", MESSAGE, "--timeout-secs", TIMEOUT, ...bindArgs);
  const local = run(LOCAL_BIN, dialArgs, "local");

  const localCode = await closed(local);
  for (const remote of remotes) remote.kill();
  await Promise.all(remotes.map(closed));
  return localCode;
}

/** The remote (listening) half, per kind. */
function listenCommand() {
  if (KIND === "group") return [`${remoteDebugEnv}${REMOTE_BIN}`, "group-listen", "--timeout-secs", TIMEOUT];
  if (KIND === "channel") {
    return [`${remoteDebugEnv}${REMOTE_BIN}`, "channel-listen", "--channel", CHANNEL, "--timeout-secs", TIMEOUT];
  }
  return [`${remoteDebugEnv}${REMOTE_BIN}`, "listen", "--timeout-secs", TIMEOUT];
}

/** The local (dialing) half, per kind. `invite` is null for a channel. */
function dialCommand(invite) {
  if (KIND === "group") return ["group-dial", "--invite", invite];
  if (KIND === "channel") return ["channel-dial", "--channel", CHANNEL];
  return ["dial", "--invite", invite];
}

/// Resolves with a child's exit code once it is gone. If it already exited,
/// "close" has fired and will never fire again — subscribing unconditionally
/// would hang the runner forever.
function closed(child) {
  return new Promise((resolve) => {
    if (child.exitCode !== null) resolve(child.exitCode);
    else if (child.signalCode !== null) resolve(0);
    else child.on("close", resolve);
  });
}

/** One conversation, one process per end. */
async function runSingle(bindArgs) {
  const remote = run("ssh", ["-o", "BatchMode=yes", HOST, listenCommand().join(" ")], "remote");

  // A DM and a group hand the dialer an invite; a channel is agreed on by name.
  const invite = KIND === "channel" ? null : await waitForInvite(remote);
  console.error(
    KIND === "channel"
      ? `[runner] channel ${CHANNEL}, dialing locally`
      : "[runner] invite received, dialing locally",
  );

  const dialArgs = [...dialCommand(invite), "--message", MESSAGE];
  dialArgs.push("--timeout-secs", TIMEOUT, ...bindArgs);
  const local = run(LOCAL_BIN, dialArgs, "local");
  const localCode = await closed(local);

  // Only a DM proves delivery from this end. A group and a channel settle at
  // Sent whatever happens, so the listening end is the one that knows: wait
  // for its verdict instead of killing it.
  let remoteCode = 0;
  if (KIND === "dm") {
    remote.kill();
    await closed(remote);
  } else {
    remoteCode = await closed(remote);
  }

  const code = localCode === 0 && remoteCode === 0 ? 0 : 1;
  await report(code);
  process.exit(code);
}

async function main() {
  const bindArgs = BIND ? ["--bind-interface", BIND] : [];
  // `--sessions N` measures one node carrying N rooms, which only the DM half
  // of the probe can set up today.
  if (SESSIONS > 1 && KIND !== "dm") {
    console.error(`--sessions ${SESSIONS} is only supported with --kind dm`);
    process.exit(2);
  }
  if (SESSIONS <= 1) {
    await runSingle(bindArgs);
    return;
  }

  const localCode = await runMany(SESSIONS, bindArgs);
  for (const topology of events.filter((e) => e.kind === "topology")) {
    console.error(
      `topology[${topology.source}]: ${topology.data.sessions} sessions on ` +
        `${topology.data.distinct_nodes} node(s), ports ${JSON.stringify(topology.data.listen_ports)}`,
    );
  }
  await report(localCode);
  process.exit(localCode === 0 ? 0 : 1);
}

await main();
