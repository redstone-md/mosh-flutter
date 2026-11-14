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
// scripts/ios-embed-moss.sh runs this from the Runner target's build phase.
import { spawnSync } from "node:child_process";
import { mkdir, rm, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const MOSS_DIR = path.resolve("moss");
const OUTPUT_DIR = path.resolve("moss-runtime", "ios");
const FRAMEWORK_DIR = path.join(OUTPUT_DIR, "Moss.framework");
const ARCHIVE_PATH = path.join(OUTPUT_DIR, "libmoss.a");

// Same pin as scripts/moss-prepare.mjs: Go 1.26.1 corrupts memory under the
// DHT's concurrent UDP.
const GO_TOOLCHAIN = "go1.25.9";
// Matches the Runner target's IPHONEOS_DEPLOYMENT_TARGET.
const MIN_IOS = "13.0";

try {
  await ensureMossCheckout();
  await mkdir(OUTPUT_DIR, { recursive: true });
  const sdk = run("xcrun", ["--sdk", "iphoneos", "--show-sdk-path"]).trim();
  const clang = run("xcrun", ["--sdk", "iphoneos", "--find", "clang"]).trim();
  const target = ["-isysroot", sdk, "-arch", "arm64", `-miphoneos-version-min=${MIN_IOS}`];

  buildArchive([clang, ...target].join(" "));
  await linkFramework(clang, target);
  console.log(`moss.ios.runtime=${FRAMEWORK_DIR}`);
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
  await rm(FRAMEWORK_DIR, { recursive: true, force: true });
  await mkdir(FRAMEWORK_DIR, { recursive: true });
  run(clang, [
    ...target,
    "-dynamiclib",
    "-install_name",
    "@rpath/Moss.framework/Moss",
    "-Wl,-all_load",
    ARCHIVE_PATH,
    "-framework",
    "CoreFoundation",
    "-framework",
    "Security",
    "-lresolv",
    "-o",
    path.join(FRAMEWORK_DIR, "Moss"),
  ]);
  await writeFile(path.join(FRAMEWORK_DIR, "Info.plist"), frameworkInfoPlist());
  await rm(ARCHIVE_PATH, { force: true });
  await rm(path.join(OUTPUT_DIR, "libmoss.h"), { force: true });
}

// App Store validation rejects an embedded framework without a bundle id,
// a platform and a minimum OS version.
function frameworkInfoPlist() {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>Moss</string>
	<key>CFBundleIdentifier</key>
	<string>app.mosh.moss</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Moss</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>iPhoneOS</string>
	</array>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>MinimumOSVersion</key>
	<string>${MIN_IOS}</string>
</dict>
</plist>
`;
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
