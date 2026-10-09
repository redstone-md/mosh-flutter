import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

// Exercise the packaging script's command boundary on Linux. Actual Mach-O
// compilation and codesign verification run in the macOS CI lane.
async function packageFixture(helperArchs = "arm64 x86_64") {
  const root = await mkdtemp(path.join(os.tmpdir(), "mosh-macos-package-"));
  try {
    const app = path.join(root, "build/macos/Build/Products/Release/mosh.app");
    const files = ["scripts/macos-package.sh", "pubspec.yaml",
      "macos/packaging/dmg-background.png", "macos/Runner/Release.entitlements",
      "mosh-media/capture/macos/Helper.entitlements"];
    for (const relative of files) {
      const destination = path.join(root, relative);
      await mkdir(path.dirname(destination), { recursive: true });
      const content = relative === "scripts/macos-package.sh"
        ? await readFile(new URL("./macos-package.sh", import.meta.url))
        : relative === "pubspec.yaml" ? "version: 1.0.0\n" : "fixture";
      await writeFile(destination, content);
    }
    for (const relative of ["MacOS/mosh", "MacOS/libmoss.dylib",
      "Frameworks/libmosh_native_media.dylib", "Helpers/mosh-camera-capture"]) {
      const destination = path.join(app, "Contents", relative);
      await mkdir(path.dirname(destination), { recursive: true });
      await writeFile(destination, "fixture");
    }
    const bin = path.join(root, "bin");
    await mkdir(bin);
    const commands = {
      lipo: 'case "$2" in *mosh-camera-capture) echo "$MOSH_TEST_HELPER_ARCHS" ;; *) echo "arm64 x86_64" ;; esac',
      codesign: 'printf "%s\\n" "$*" >> "$MOSH_TEST_SIGN_LOG"\ncase "$1" in -dvv) echo "Authority=Mosh Self-Signed Code Signing" >&2 ;; esac',
      "create-dmg": 'for arg in "$@"; do previous=${last:-}; last=$arg; done\ntouch "$previous"',
    };
    for (const [name, body] of Object.entries(commands)) {
      await writeFile(path.join(bin, name), `#!/usr/bin/env bash\n${body}\n`, { mode: 0o755 });
    }
    const signLog = path.join(root, "sign.log");
    const result = spawnSync("bash", [path.join(root, "scripts/macos-package.sh")], {
      encoding: "utf8",
      env: { ...process.env, PATH: `${bin}${path.delimiter}${process.env.PATH}`,
        MOSH_SIGN_IDENTITY: "fixture-identity", MOSH_MACOS_UNIVERSAL: "true",
        MOSH_TEST_HELPER_ARCHS: helperArchs, MOSH_TEST_SIGN_LOG: signLog },
    });
    return { ...result, signing: await readFile(signLog, "utf8").catch(() => "") };
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

test("universal packaging rejects a camera helper missing its x86_64 slice", async () => {
  const result = await packageFixture("arm64");
  assert.equal(result.status, 1, result.stdout + result.stderr);
  assert.match(result.stderr, /no x86_64 slice.*mosh-camera-capture/);
});

test("packaging signs the camera helper with inheritance before sealing the app", async () => {
  const result = await packageFixture();
  assert.equal(result.status, 0, result.stdout + result.stderr);
  const commands = result.signing.split("\n");
  const helper = commands.findIndex((line) => line.includes("--force")
    && line.includes("Helper.entitlements") && line.endsWith("mosh-camera-capture"));
  const app = commands.findIndex((line) => line.includes("--force")
    && line.includes("Release.entitlements") && line.endsWith("mosh.app"));
  assert.ok(helper >= 0, "the camera helper must be signed with its own entitlements");
  assert.ok(helper < app, "nested code must be signed before the app seal");
});
