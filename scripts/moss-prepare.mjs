#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { mkdir, rm, stat } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

// Build output lands at the repo root `moss-runtime/` -- the canonical
// candidate `moss_runtime.rs::default_candidate_paths` resolves from the
// repo root (current_dir/moss-runtime/moss.dll).
const TARGET_DIR = path.resolve("moss-runtime");
const MOSS_DIR = path.resolve("moss");
const OUTPUT_NAME = process.platform === "win32" ? "moss.dll" : process.platform === "darwin" ? "libmoss.dylib" : "libmoss.so";
const OUTPUT_PATH = path.join(TARGET_DIR, OUTPUT_NAME);

// Pin the Go toolchain to 1.25.x. Go 1.26.1's Windows runtime has a regression
// that corrupts memory (0xc0000005) under the heavy concurrent UDP the DHT
// drives, crashing the client after minutes; 1.25 is verified stable (13 min /
// 259 msgs, DHT on, 0% loss). GOTOOLCHAIN forces it regardless of the builder's
// local Go, since the go.mod `toolchain` line is only a minimum.
const GO_ENV = { GOTOOLCHAIN: "go1.25.9" };

// macOS apps ship universal (arm64 + x86_64) so one DMG covers Apple
// Silicon and the remaining Intel Macs. Cross-cgo from either host arch
// works with the SDK clang (`-arch`); lipo staples the slices together.
// Other platforms build for the host arch only.
const DARWIN_SLICES = [
  { goarch: "arm64", clangArch: "arm64" },
  { goarch: "amd64", clangArch: "x86_64" },
];

await ensureMossCheckout();

try {
  await mkdir(TARGET_DIR, { recursive: true });

  if (process.platform === "darwin") {
    await buildUniversalLibrary();
  } else {
    buildHostLibrary();
  }

  await removeGeneratedHeader();
  console.log(`moss.runtime=${OUTPUT_PATH}`);
} catch (error) {
  console.error(`moss-prepare: ${error.message}`);
  process.exitCode = 1;
}

// -trimpath drops build-machine paths from the binary (reproducible, no
// leaked usernames); -s -w drop the symbol table and DWARF, about a third
// of the library. Go panics still print stack traces without either.
function buildLibrary(outputPath, extraEnv = {}) {
  const result = spawnSync(
    "go",
    ["build", "-trimpath", "-ldflags=-s -w", "-buildmode=c-shared", "-o", outputPath, "./cmd/moss-ffi"],
    { cwd: MOSS_DIR, stdio: "inherit", env: { ...process.env, ...GO_ENV, ...extraEnv } },
  );

  if (result.status !== 0) {
    throw new Error(`go build failed with status ${result.status ?? 1} (GOARCH=${extraEnv.GOARCH ?? "host"})`);
  }
}

function buildHostLibrary() {
  buildLibrary(OUTPUT_PATH);
}

async function buildUniversalLibrary() {
  const sliceDir = path.join(TARGET_DIR, ".universal-tmp");
  await mkdir(sliceDir, { recursive: true });

  // finally, not process.exit paths: a failed slice or lipo must still
  // clean .universal-tmp, or moss-runtime/ litters with half-built slices.
  try {
    const slicePaths = DARWIN_SLICES.map((slice) => path.join(sliceDir, `libmoss.${slice.goarch}.dylib`));

    for (const [index, slice] of DARWIN_SLICES.entries()) {
      // An explicit GOARCH (even one matching the host) makes Go treat the
      // build as a cross-compile and default CGO_ENABLED to 0 -- and
      // c-shared cannot link without cgo. Force it on for every slice.
      buildLibrary(slicePaths[index], {
        GOARCH: slice.goarch,
        CGO_ENABLED: "1",
        CC: `clang -arch ${slice.clangArch}`,
      });
    }

    const result = spawnSync("lipo", ["-create", "-output", OUTPUT_PATH, ...slicePaths], { stdio: "inherit" });
    if (result.status !== 0) {
      throw new Error(`lipo failed with status ${result.status ?? 1}`);
    }
  } finally {
    // The per-slice builds drop a header next to each -o output; the temp
    // dir holds them all and disappears with it -- also on failure.
    await rm(sliceDir, { recursive: true, force: true });
  }

  // lipo leaves the fat dylib unsigned: the Apple Silicon loader requires
  // at least an ad-hoc signature, and Xcode's CodeSign refuses to seal an
  // app containing a nested unsigned dylib ("code object is not signed
  // at all"). Sign it here, at the source, so local builds, CI and the
  // DMG all get a signed library and nothing has to re-sign inside a
  // sealed bundle.
  const signing = spawnSync("codesign", ["--force", "--sign", "-", OUTPUT_PATH], { stdio: "inherit" });
  if (signing.status !== 0) {
    throw new Error(`codesign failed with status ${signing.status ?? 1}`);
  }
}

async function removeGeneratedHeader() {
  const headerName = process.platform === "win32" ? "moss.h" : "libmoss.h";
  await rm(path.join(TARGET_DIR, headerName), { force: true });
}

async function ensureMossCheckout() {
  try {
    await stat(path.join(MOSS_DIR, "cmd", "moss-ffi"));
  } catch {
    throw new Error(`Moss checkout not found at ${MOSS_DIR}`);
  }
}
