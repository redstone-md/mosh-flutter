import assert from "node:assert/strict";
import test from "node:test";
import { libmpvRelease, notices } from "./third-party-licenses.mjs";

const SEPARATOR = `\n${"-".repeat(80)}\n`;

test("components under one text share an entry, in a stable order", () => {
  const file = notices([
    { names: ["serde"], text: "MIT text\r\n" },
    { names: ["golang.org/x/sys"], text: "BSD text" },
    { names: ["anyhow", "serde"], text: "MIT text" },
  ]);
  assert.equal(file, `anyhow\nserde\n\nMIT text${SEPARATOR}golang.org/x/sys\n\nBSD text\n`);
});

test("a text that would split the file is refused", () => {
  assert.throws(() => notices([{ names: ["dashes"], text: `a${SEPARATOR}b` }]), /dashes/);
});

test("the release page comes from the build a plugin downloads", () => {
  const cmake = [
    'set(LIBMPV "mpv-dev-x86_64-20230924-git-652a1dd.7z")',
    'set(LIBMPV_URL "https://github.com/media-kit/libmpv-win32-video-build/releases/download/2023-09-24/${LIBMPV}")',
    'set(ANGLE_URL "https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z")',
  ].join("\n");
  assert.equal(libmpvRelease(cmake),
    "https://github.com/media-kit/libmpv-win32-video-build/releases/tag/2023-09-24");
  const makefile = [
    "MPV_XCFRAMEWORKS_VERSION=v0.6.0",
    "\tcurl -L \\",
    "\t\thttps://github.com/media-kit/libmpv-darwin-build/releases/download/${MPV_XCFRAMEWORKS_VERSION}/libmpv-xcframeworks_${MPV_XCFRAMEWORKS_VERSION}_macos-universal-video-default.tar.gz \\",
  ].join("\n");
  assert.equal(libmpvRelease(makefile),
    "https://github.com/media-kit/libmpv-darwin-build/releases/tag/v0.6.0");
  assert.throws(() => libmpvRelease("set(MPV_URL \"https://example.test/mpv.7z\")"), /libmpv/);
});
