#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { access, readFile } from "node:fs/promises";
import path from "node:path";
import { setTimeout } from "node:timers/promises";
import { fileURLToPath, pathToFileURL } from "node:url";

// Run after flutter pub get. Respect the dependency's compiler and targets;
// installing Mosh's toolchain does not prepare this package's native hook.
export async function prepareAndroidNativeHooks({
  packageConfig = ".dart_tool/package_config.json",
  retryDelayMs = 5000,
} = {}) {
  const configFile = path.resolve(packageConfig);
  const config = JSON.parse(await readFile(configFile, "utf8"));
  const pkg = config.packages.find((entry) => entry.name === "irondash_engine_context");
  if (!pkg) throw new Error("irondash_engine_context is missing; run flutter pub get");
  const packageRoot = fileURLToPath(new URL(pkg.rootUri, pathToFileURL(configFile)));
  const cwd = path.join(packageRoot, "android", "rust");
  await access(path.join(cwd, "rust-toolchain.toml"));

  for (let attempt = 1; attempt <= 3; attempt++) {
    const result = spawnSync("rustup", [
      "toolchain", "install", "--profile", "minimal", "--no-update", "--no-self-update",
    ], { cwd, stdio: "inherit" });
    if (result.error) throw result.error;
    if (result.status === 0) return;
    console.warn(`Android native hook Rust installation failed (${attempt}/3)`);
    if (attempt < 3) await setTimeout(retryDelayMs * attempt);
  }
  throw new Error("Android native hook Rust installation failed after 3 attempts");
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try {
    await prepareAndroidNativeHooks();
  } catch (error) {
    console.error(`android-native-hooks-prepare: ${error.message}`);
    process.exitCode = 1;
  }
}
