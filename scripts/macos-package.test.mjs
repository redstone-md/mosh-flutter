import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

// Exercise the packaging script's command boundary on Linux. Actual Mach-O
// compilation, codesign verification and notarization run in the macOS CI
// lane. `notaryStatus` asks for notarization, hands the script an App Store
// Connect key (unless `notaryKey` is false) and makes the stubbed notary
// service answer with that status.
async function packageFixture({ helperArchs = "arm64 x86_64", notaryStatus, notaryKey = true } = {}) {
  const root = await mkdtemp(path.join(os.tmpdir(), "mosh-macos-package-"));
  try {
    const app = path.join(root, "build/macos/Build/Products/Release/mosh.app");
    const files = ["scripts/macos-package.sh", "scripts/macos-notarize.sh", "pubspec.yaml",
      "macos/packaging/dmg-background.png", "macos/Runner/Release.entitlements",
      "mosh-media/capture/macos/Helper.entitlements"];
    for (const relative of files) {
      const destination = path.join(root, relative);
      await mkdir(path.dirname(destination), { recursive: true });
      const content = relative.startsWith("scripts/")
        ? await readFile(new URL(path.basename(relative), import.meta.url))
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
      codesign: 'printf "%s\\n" "$*" >> "$MOSH_TEST_SIGN_LOG"\ncase "$1" in -dvv) echo "Authority=Developer ID Application: Fixture (FIXTURE123)" >&2 ;; esac',
      "create-dmg": 'for arg in "$@"; do previous=${last:-}; last=$arg; done\ntouch "$previous"',
      xcrun: [
        'case "$1 $2" in',
        '  "notarytool submit") printf \'{"id":"fixture-id","status":"%s"}\\n\' "$MOSH_TEST_NOTARY_STATUS" ;;',
        '  "notarytool log") echo "fixture notary log" ;;',
        '  "stapler staple") printf ticket >> "$3" ;;',
        "esac",
      ].join("\n"),
      plutil: 'node -e \'console.log(JSON.parse(require("fs").readFileSync(process.argv[2], "utf8"))[process.argv[1]])\' "$2" "$4"',
      spctl: "true",
    };
    for (const [name, body] of Object.entries(commands)) {
      await writeFile(path.join(bin, name), `#!/usr/bin/env bash\n${body}\n`, { mode: 0o755 });
    }
    const signLog = path.join(root, "sign.log");
    // Explicit either way, so a developer's own App Store Connect key in the
    // environment never reaches the script.
    const notary = notaryStatus === undefined
      ? { MOSH_NOTARIZE: "false", APP_STORE_CONNECT_ISSUER_ID: "", APP_STORE_CONNECT_KEY_ID: "",
        APP_STORE_CONNECT_KEY_P8_BASE64: "" }
      : { MOSH_NOTARIZE: "true", APP_STORE_CONNECT_ISSUER_ID: "fixture-issuer", APP_STORE_CONNECT_KEY_ID: "FIXTURE",
        APP_STORE_CONNECT_KEY_P8_BASE64: notaryKey ? Buffer.from("fixture key").toString("base64") : "",
        MOSH_TEST_NOTARY_STATUS: notaryStatus };
    const result = spawnSync("bash", [path.join(root, "scripts/macos-package.sh")], {
      encoding: "utf8",
      env: { ...process.env, PATH: `${bin}${path.delimiter}${process.env.PATH}`,
        MOSH_SIGN_IDENTITY: "fixture-identity", MOSH_MACOS_UNIVERSAL: "true",
        MOSH_TEST_HELPER_ARCHS: helperArchs, MOSH_TEST_SIGN_LOG: signLog, ...notary },
    });
    const dmg = path.join(root, "build/macos-dist/Mosh_1.0.0_universal.dmg");
    return { ...result, signing: await readFile(signLog, "utf8").catch(() => ""),
      dmg: await readFile(dmg).catch(() => null),
      checksum: await readFile(`${dmg}.sha256`, "utf8").catch(() => null) };
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

test("universal packaging rejects a camera helper missing its x86_64 slice", async () => {
  const result = await packageFixture({ helperArchs: "arm64" });
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


test("a notarized DMG is checksummed after the ticket is stapled to it", async () => {
  const result = await packageFixture({ notaryStatus: "Accepted" });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.equal(result.dmg.toString(), "ticket", "the stapled ticket must be in the shipped DMG");
  const hash = createHash("sha256").update(result.dmg).digest("hex");
  assert.equal(result.checksum, `${hash}  Mosh_1.0.0_universal.dmg\n`);
  assert.match(result.signing, /--timestamp --sign fixture-identity \S*\.dmg$/m,
    "Gatekeeper needs the DMG itself signed");
});

test("a rejected notarization fails the package and prints Apple's log", async () => {
  const result = await packageFixture({ notaryStatus: "Invalid" });
  assert.equal(result.status, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /fixture notary log/);
  assert.match(result.stderr, /notarization ended with status 'Invalid'/);
  assert.equal(result.checksum, null, "no checksum may vouch for a DMG Apple rejected");
});

test("a release without the App Store Connect key fails instead of shipping an unnotarized DMG", async () => {
  const result = await packageFixture({ notaryStatus: "Accepted", notaryKey: false });
  assert.equal(result.status, 1, result.stdout + result.stderr);
  assert.match(result.stderr, /APP_STORE_CONNECT_KEY_P8_BASE64 is empty/);
  assert.equal(result.checksum, null);
});
