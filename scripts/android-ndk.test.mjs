import assert from "node:assert/strict";
import path from "node:path";
import { test } from "node:test";
import { ndkToolchain } from "./support/android-ndk.mjs";

const target = { triple: "aarch64-linux-android", api: 26 };
const bin = (tag) => path.join("/ndk", "toolchains", "llvm", "prebuilt", tag, "bin");

test("Windows hosts get the windows prebuilt with its .cmd clang wrappers", () => {
  const tools = bin("windows-x86_64");
  assert.deepEqual(ndkToolchain("/ndk", target, "win32"), {
    cc: path.join(tools, "aarch64-linux-android26-clang.cmd"),
    cxx: path.join(tools, "aarch64-linux-android26-clang++.cmd"),
    ar: path.join(tools, "llvm-ar.exe"),
  });
});

test("macOS hosts get the darwin prebuilt", () => {
  assert.equal(ndkToolchain("/ndk", target, "darwin").cc,
    path.join(bin("darwin-x86_64"), "aarch64-linux-android26-clang"));
});

test("a host the NDK does not ship for fails before any build starts", () => {
  assert.throws(() => ndkToolchain("/ndk", target, "freebsd"), /Unsupported NDK host platform: freebsd/);
});
