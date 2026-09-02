#!/usr/bin/env node
// Cross-compiles moss to libmoss.so for android/arm64. Requires the Android
// NDK (ANDROID_NDK_HOME). NOT verified in this commit — the NDK was absent
// when this script was written; verify with `node scripts/moss-prepare-android.mjs`
// once the NDK is installed.
//
// The output lands in android/app/src/main/jniLibs/arm64-v8a/libmoss.so so AGP
// packages it into the APK, and Android's dlopen resolves the bare name
// "libmoss.so" against the app's nativeLibraryDir at runtime (see
// mosh-core/src/moss_runtime.rs default_candidate_paths).
import { spawnSync } from "node:child_process";
import { promises as fs, statSync } from "node:fs";
import { mkdir, rm } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import os from "node:os";

const OUTPUT_DIR = path.resolve("android", "app", "src", "main", "jniLibs", "arm64-v8a");
const OUTPUT_NAME = "libmoss.so";
const OUTPUT_PATH = path.join(OUTPUT_DIR, OUTPUT_NAME);
const MOSS_DIR = path.resolve("moss");

// NDK API 24 — the cargokit minSdk 21 floor plus a stable, widely supported
// API level. The clang wrapper is named <triple><api>-clang.
const NDK_API_LEVEL = "24";
const NDK_TRIPLE = "aarch64-linux-android";

function ndkHostTag() {
  switch (process.platform) {
    case "win32":
      return "windows-x86_64";
    case "linux":
      return "linux-x86_64";
    case "darwin":
      return "darwin-x86_64";
    default:
      throw new Error(`Unsupported NDK host platform: ${process.platform}`);
  }
}

function resolveNdkRoot() {
  const root = process.env.ANDROID_NDK_HOME ?? process.env.ANDROID_NDK_ROOT;
  if (!root) {
    throw new Error(
      "ANDROID_NDK_HOME not set; install the Android NDK and set ANDROID_NDK_HOME",
    );
  }
  return root;
}

async function resolveToolchain() {
  const ndkRoot = resolveNdkRoot();
  const prebuilt = path.join(ndkRoot, "toolchains", "llvm", "prebuilt", ndkHostTag());
  const cc = path.join(prebuilt, "bin", `${NDK_TRIPLE}${NDK_API_LEVEL}-clang`);
  const cxx = path.join(prebuilt, "bin", `${NDK_TRIPLE}${NDK_API_LEVEL}-clang++`);
  // Go reads cgo flags from its stored env (GOENV file), NOT only process env.
  // On this dev machine the GOENV pins CGO_LDFLAGS/CGO_CFLAGS at a Windows/x86
  // libolm.a + headers (left over from an earlier setup). moss has NO libolm
  // dependency (crypto is pure-Go: flynn/noise + golang.org/x/crypto), so
  // linking the Windows libolm into an android/arm64 .so only emitted ld.lld
  // "archive member is neither ET_REL nor LLVM bitcode" warnings — the linker
   // skipped the wrong-format members and nothing olm reached the .so symbol
   // table. Pointing GOENV at an empty file for this invocation makes go read
   // NO stored cgo flags, so the link line stays honest (only the NDK
   // CC/CXX below supply the C toolchain). We do NOT touch the user's real
   // GOENV; the empty file is a per-invocation override.
  const cleanGoEnv = await fs.open(path.join(os.tmpdir(), `mosh-goenv-android-${process.pid}.txt`), "w");
  await cleanGoEnv.close();
  const cleanGoEnvPath = path.join(os.tmpdir(), `mosh-goenv-android-${process.pid}.txt`);

  // Verify the CC wrapper exists so a misconfigured NDK_HOME fails fast with
  // the exact path that was expected, not a cryptic go/cgo error later.
  try {
    statSync(cc);
  } catch {
    await rm(cleanGoEnvPath, { force: true });
    throw new Error(
      `NDK clang not found at ${cc}; ensure ANDROID_NDK_HOME points at an installed NDK with API ${NDK_API_LEVEL} toolchains`,
    );
  }

  return { cc, cxx, cleanGoEnvPath };
}

async function main() {
  const { cc, cxx, cleanGoEnvPath } = await resolveToolchain();
  await ensureMossCheckout();
  await mkdir(OUTPUT_DIR, { recursive: true });

  const result = spawnSync(
    "go",
    // Same flags as moss-prepare.mjs: no build paths, no symbols, no DWARF.
    ["build", "-trimpath", "-ldflags=-s -w", "-buildmode=c-shared", "-o", OUTPUT_PATH, "./cmd/moss-ffi"],
    {
      cwd: MOSS_DIR,
      stdio: "inherit",
      env: {
        ...process.env,
        CGO_ENABLED: "1",
       GOOS: "android",
       GOARCH: "arm64",
       CC: cc,
       CXX: cxx,
        GOTOOLCHAIN: "go1.25.9",
        // Use the per-invocation empty GOENV so go reads NO stored cgo flags
        // (see resolveToolchain); CGO_LDFLAGS/CFLAGS explicitly empty too as
        // belt-and-suspenders in case a future go honors process env over
        // the empty GOENV file.
        GOENV: cleanGoEnvPath,
        CGO_LDFLAGS: "",
        CGO_CFLAGS: "",
      },
    },
  );

  if (result.status !== 0) {
    await rm(cleanGoEnvPath, { force: true });
    process.exit(result.status ?? 1);
  }

  await removeGeneratedHeader();
  await rm(cleanGoEnvPath, { force: true });
  console.log(`mosh.android.runtime=${OUTPUT_PATH}`);
}

async function removeGeneratedHeader() {
  // c-shared emits libmoss.h next to the .so; the host does not need it.
  await rm(path.join(OUTPUT_DIR, "libmoss.h"), { force: true });
}

async function ensureMossCheckout() {
  try {
    await fs.stat(path.join(MOSS_DIR, "cmd", "moss-ffi"));
  } catch {
    throw new Error(`Moss checkout not found at ${MOSS_DIR}`);
  }
}

await main();
