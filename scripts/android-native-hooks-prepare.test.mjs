import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";
import { prepareAndroidNativeHooks } from "./android-native-hooks-prepare.mjs";

const fakeRustup = `#!/usr/bin/env node
const fs = require('node:fs');
const args = process.argv.slice(2);
const attempts = fs.existsSync('attempts') ? Number(fs.readFileSync('attempts')) : 0;
if (args[0] === 'toolchain' && args[1] === 'install') {
  fs.writeFileSync('attempts', String(attempts + 1));
  if (fs.existsSync('failures') && attempts < Number(fs.readFileSync('failures'))) {
    console.error('Network is unreachable');
    process.exit(1);
  }
  const spec = fs.readFileSync('rust-toolchain.toml', 'utf8');
  fs.writeFileSync('installed', spec);
} else if (args.join(' ') === 'show active-toolchain') {
  if (!fs.existsSync('installed')) {
    console.error('Rust 1.97.1 download failed: Network is unreachable');
    process.exit(1);
  }
  console.log(fs.readFileSync('installed', 'utf8'));
} else {
  process.exit(2);
}
`;

async function fixture(run) {
  const root = await mkdtemp(path.join(os.tmpdir(), "mosh-android-hooks-"));
  const originalPath = process.env.PATH;
  try {
    const crate = path.join(root, "pub cache", "engine", "android", "rust");
    const bin = path.join(root, "bin");
    const config = path.join(root, ".dart_tool", "package_config.json");
    await Promise.all([mkdir(crate, { recursive: true }), mkdir(bin), mkdir(path.dirname(config))]);
    await writeFile(path.join(crate, "rust-toolchain.toml"), '[toolchain]\nchannel = "1.97.1"\ntargets = ["aarch64-linux-android"]\n');
    await writeFile(config, JSON.stringify({ packages: [{
      name: "irondash_engine_context", rootUri: "../pub%20cache/engine/",
    }] }));
    await writeFile(path.join(bin, "rustup"), fakeRustup, { mode: 0o755 });
    process.env.PATH = `${bin}${path.delimiter}${originalPath}`;
    await run({ crate, config });
  } finally {
    process.env.PATH = originalPath;
    await rm(root, { recursive: true, force: true });
  }
}

test("preparation makes the dependency's pinned compiler and Android target available offline", async () => {
  await fixture(async ({ crate, config }) => {
    const probe = () => spawnSync("rustup", ["show", "active-toolchain"], { cwd: crate, encoding: "utf8" });
    assert.equal(probe().status, 1);
    await prepareAndroidNativeHooks({ packageConfig: config, retryDelayMs: 0 });
    const ready = probe();
    assert.equal(ready.status, 0, ready.stderr);
    assert.match(ready.stdout, /1\.97\.1/);
    assert.match(ready.stdout, /aarch64-linux-android/);
    assert.equal(await readFile(path.join(crate, "attempts"), "utf8"), "1");
  });
});

test("absolute package URIs work and a transient install failure is retried", async () => {
  await fixture(async ({ crate, config }) => {
    await writeFile(config, JSON.stringify({ packages: [{ name: "irondash_engine_context", rootUri: pathToFileURL(path.resolve(crate, "../..")).href }] }));
    await writeFile(path.join(crate, "failures"), "1");
    await prepareAndroidNativeHooks({ packageConfig: config, retryDelayMs: 0 });
    assert.equal(await readFile(path.join(crate, "attempts"), "utf8"), "2");
    assert.match(await readFile(path.join(crate, "installed"), "utf8"), /1\.97\.1/);
  });
});

test("persistent install failure stops after three attempts", async () => {
  await fixture(async ({ crate, config }) => {
    await writeFile(path.join(crate, "failures"), "99");
    await assert.rejects(prepareAndroidNativeHooks({ packageConfig: config, retryDelayMs: 0 }), /3 attempts/);
    assert.equal(await readFile(path.join(crate, "attempts"), "utf8"), "3");
    assert.equal(spawnSync("rustup", ["show", "active-toolchain"], { cwd: crate }).status, 1);
  });
});

test("a missing package or toolchain file fails before selecting a default compiler", async () => {
  await fixture(async ({ crate, config }) => {
    await rm(path.join(crate, "rust-toolchain.toml"));
    await assert.rejects(prepareAndroidNativeHooks({ packageConfig: config }), /ENOENT/);
    await assert.rejects(readFile(path.join(crate, "attempts")), /ENOENT/);
    await writeFile(config, JSON.stringify({ packages: [] }));
    await assert.rejects(prepareAndroidNativeHooks({ packageConfig: config }), /irondash_engine_context.*flutter pub get/);
  });
});

test("the CI command succeeds only after preparation and reports missing dependencies", async () => {
  await fixture(async ({ crate, config }) => {
    const script = fileURLToPath(new URL("./android-native-hooks-prepare.mjs", import.meta.url));
    const run = () => spawnSync(process.execPath, [script], {
      cwd: path.dirname(path.dirname(config)), encoding: "utf8",
    });
    const ready = run();
    assert.equal(ready.status, 0, ready.stderr);
    assert.match(await readFile(path.join(crate, "installed"), "utf8"), /1\.97\.1/);
    await writeFile(config, JSON.stringify({ packages: [] }));
    const failed = run();
    assert.equal(failed.status, 1);
    assert.match(failed.stderr, /irondash_engine_context.*flutter pub get/);
  });
});
