#!/usr/bin/env node
// Builds Moss for iPhone (ios/arm64) as moss-runtime/ios/Moss.framework.
// macOS only: it needs Xcode's iPhoneOS SDK.
//
// Go cannot build a shared library for iOS (-buildmode=c-shared stops at
// darwin), only a static archive. The archive is linked into a dynamic
// framework, so the app embeds and signs it like any other framework and
// mosh-core opens it with the same dlopen as on the desktop
// (MOSS_LIBRARY_NAME in mosh-core/src/moss_runtime.rs).
//
// scripts/ios-embed-frameworks.sh runs this from the Runner target's build phase.
import { spawnSync } from "node:child_process";
import { mkdir, rm, stat } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { frameworkInstallName, MIN_IOS, writeFramework } from "./support/ios-framework.mjs";

const MOSS_DIR = path.resolve("moss");
const OUTPUT_DIR = path.resolve("moss-runtime", "ios");
const ARCHIVE_PATH = path.join(OUTPUT_DIR, "libmoss.a");

// Same pin as scripts/moss-prepare.mjs: Go 1.26.1 corrupts memory under the
// DHT's concurrent UDP.
const GO_TOOLCHAIN = "go1.25.9";

try {
  await ensureMossCheckout();
  await mkdir(OUTPUT_DIR, { recursive: true });
  const sdk = run("xcrun", ["--sdk", "iphoneos", "--show-sdk-path"]).trim();
  const clang = run("xcrun", ["--sdk", "iphoneos", "--find", "clang"]).trim();
  const target = ["-isysroot", sdk, "-arch", "arm64", `-miphoneos-version-min=${MIN_IOS}`];

  buildArchive([clang, ...target].join(" "));
  console.log(`moss.ios.runtime=${await linkFramework(clang, target)}`);
} catch (error) {
  console.error(`moss-prepare-ios: ${error.message}`);
  process.exitCode = 1;
}

function buildArchive(cc) {
  run(
    "go",
    ["build", "-trimpath", "-ldflags=-s -w", "-buildmode=c-archive", "-o", ARCHIVE_PATH, "./cmd/moss-ffi"],
    {
      cwd: MOSS_DIR,
      env: {
        ...process.env,
        // Only the iPhoneOS flags above: host cgo flags from the caller or a
        // stored `go env -w` would point the cross-build at macOS inputs.
        GOENV: "off",
        CGO_CFLAGS: "",
        CGO_CPPFLAGS: "",
        CGO_CXXFLAGS: "",
        CGO_LDFLAGS: "",
        GOTOOLCHAIN: GO_TOOLCHAIN,
        GOOS: "ios",
        GOARCH: "arm64",
        CGO_ENABLED: "1",
        CC: cc,
      },
    },
  );
}

// -all_load keeps every exported Moss_* symbol: nothing in the framework
// references them, mosh-core looks them up at runtime. The Go runtime uses
// CoreFoundation and Security (certificates) and libresolv (DNS).
async function linkFramework(clang, target) {
  const library = path.join(OUTPUT_DIR, "Moss");
  run(clang, [
    ...target,
    "-dynamiclib",
    "-install_name",
    frameworkInstallName("Moss"),
    "-Wl,-all_load",
    ARCHIVE_PATH,
    "-framework",
    "CoreFoundation",
    "-framework",
    "Security",
    "-lresolv",
    "-o",
    library,
  ]);
  await rm(ARCHIVE_PATH, { force: true });
  await rm(path.join(OUTPUT_DIR, "libmoss.h"), { force: true });
  return writeFramework({ directory: OUTPUT_DIR, name: "Moss", bundleId: "app.mosh.moss", library });
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { stdio: ["ignore", "pipe", "inherit"], encoding: "utf8", ...options });
  if (result.status !== 0) {
    throw new Error(`${command} ${args[0]} failed with status ${result.status ?? 1}`);
  }
  return result.stdout;
}

async function ensureMossCheckout() {
  try {
    await stat(path.join(MOSS_DIR, "cmd", "moss-ffi"));
  } catch {
    throw new Error(`Moss checkout not found at ${MOSS_DIR}`);
  }
}
