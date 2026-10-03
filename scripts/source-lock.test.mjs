import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { withSourceLock } from "./support/source-lock.mjs";

test("concurrent processes recover dead claims without sharing the critical section", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "mosh-source-lock-"));
  const counter = path.join(directory, "counter");
  const module = new URL("./support/source-lock.mjs", import.meta.url).href;
  const holder = spawn(process.execPath, ["-e", "setInterval(() => {}, 1000)"], { stdio: "ignore" });
  const exited = once(holder, "exit");
  holder.kill("SIGKILL");
  await exited;
  await writeFile(counter, "0");
  await writeFile(path.join(directory, "dead.json"), JSON.stringify({ pid: holder.pid, choosing: true, ticket: 0 }));
  const worker = `
    import { readFile, writeFile, open, unlink } from 'node:fs/promises';
    import path from 'node:path';
    const { withSourceLock } = await import(process.argv[1]);
    const directory = process.argv[2];
    for (let i = 0; i < 3; i++) await withSourceLock(directory, async () => {
      const marker = path.join(directory, 'exclusive');
      const handle = await open(marker, 'wx');
      try {
        const counter = path.join(directory, 'counter');
        const value = Number(await readFile(counter, 'utf8'));
        await new Promise(resolve => setTimeout(resolve, 10));
        await writeFile(counter, String(value + 1));
      } finally {
        await handle.close();
        await unlink(marker);
      }
    });
  `;
  try {
    await completeWorkers(Array.from({ length: 12 }, async () => {
      const child = spawn(process.execPath, ["--input-type=module", "-e", worker, module, directory]);
      let errors = "";
      child.stderr.on("data", (chunk) => { errors += chunk; });
      const [code] = await once(child, "exit");
      assert.equal(code, 0, errors);
    }));
    assert.equal(await readFile(counter, "utf8"), "36");
    assert.deepEqual(await readdir(directory), ["counter"]);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("failed actions release their claim and same-process callers serialize", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "mosh-source-lock-"));
  try {
    await assert.rejects(withSourceLock(directory, () => { throw new Error("failed action"); }), /failed action/);
    let active = 0;
    await completeWorkers(Array.from({ length: 8 }, () => withSourceLock(directory, async () => {
      assert.equal(++active, 1);
      await new Promise((resolve) => setTimeout(resolve, 5));
      assert.equal(active--, 1);
    })));
    assert.deepEqual(await readdir(directory), []);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

// Finish every caller before cleanup, including when one of them fails.
async function completeWorkers(workers) {
  for (const worker of await Promise.allSettled(workers)) {
    if (worker.status === "rejected") throw worker.reason;
  }
}
