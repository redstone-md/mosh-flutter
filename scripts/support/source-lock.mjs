import { randomUUID } from "node:crypto";
import { mkdir, readFile, readdir, rename, rm, writeFile } from "node:fs/promises";
import path from "node:path";

const removalOptions = { recursive: true, force: true, maxRetries: 20, retryDelay: 20 };

/** Lamport's bakery lock: each process owns a unique claim, so recovery cannot delete a new owner. */
export async function withSourceLock(directory, action) {
  await mkdir(directory, { recursive: true });
  const claim = path.join(directory, `${process.pid}-${randomUUID()}.json`);
  const owner = { pid: process.pid, choosing: true, ticket: 0 };
  await publish(claim, owner);
  try {
    const claims = await liveClaims(directory);
    owner.ticket = 1 + Math.max(0, ...claims.map(({ state }) => state.ticket));
    owner.choosing = false;
    await publish(claim, owner);
    await waitForTurn(directory, claim, owner.ticket);
    return await action();
  } finally {
    await rm(claim, removalOptions);
  }
}

async function publish(claim, state) {
  const pending = `${claim}.pending`;
  await writeFile(pending, JSON.stringify(state));
  const deadline = Date.now() + 5_000;
  while (true) {
    try {
      await rename(pending, claim);
      return;
    } catch (error) {
      // Windows readers can briefly deny replacement until their handles close.
      if (!["EPERM", "EACCES", "EBUSY"].includes(error.code) || Date.now() >= deadline) throw error;
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
  }
}

async function liveClaims(directory) {
  const claims = [];
  for (const name of await readdir(directory)) {
    if (!name.endsWith(".json")) continue;
    const claim = path.join(directory, name);
    const state = await readFile(claim, "utf8").then(JSON.parse).catch((error) => {
      if (error.code !== "ENOENT") throw error;
      return null;
    });
    if (!state) continue;
    if (alive(state.pid)) claims.push({ claim, state });
    else await rm(claim, removalOptions);
  }
  return claims;
}

function alive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    if (error.code === "ESRCH") return false;
    throw error;
  }
}

async function waitForTurn(directory, claim, ticket) {
  const deadline = Date.now() + 60_000;
  while (true) {
    const blocked = (await liveClaims(directory)).some(({ claim: other, state }) =>
      other !== claim && (state.choosing || state.ticket < ticket ||
        (state.ticket === ticket && other < claim)));
    if (!blocked) return;
    if (Date.now() >= deadline) throw new Error(`OpenMLS preparation lock timed out: ${directory}`);
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
}
