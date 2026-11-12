#!/usr/bin/env node
// Builds the call engine (mosh-media/webrtc) for Android arm64 into jniLibs,
// with its libwebrtc Java classes and license notices. Gradle runs it and
// passes our libwebrtc build, which it fetches from Maven Central, as
// MOSH_LIBWEBRTC_ARCHIVE (android/app/build.gradle.kts).
import { spawnSync } from 'node:child_process';
import { copyFile, mkdir, rm } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { prepareLibwebrtc, prepareLiveKitWebrtc } from './livekit-webrtc-prepare.mjs';
import { nativeProtoc } from './support/native-protoc.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ndk = process.env.ANDROID_NDK_HOME;
if (!ndk) throw new Error('ANDROID_NDK_HOME is required');
const archive = process.env.MOSH_LIBWEBRTC_ARCHIVE;
if (!archive) throw new Error('MOSH_LIBWEBRTC_ARCHIVE is required: build the APK through Gradle');
const target = 'aarch64-linux-android';
const tool = path.join(ndk, 'toolchains/llvm/prebuilt/linux-x86_64/bin');
const targetRoot = path.join(root, '.dart_tool/native-media/target');
const env = { ...process.env, PROTOC: await nativeProtoc(root),
  CC_aarch64_linux_android: path.join(tool, 'aarch64-linux-android26-clang'),
  CXX_aarch64_linux_android: path.join(tool, 'aarch64-linux-android26-clang++'),
  AR_aarch64_linux_android: path.join(tool, 'llvm-ar'),
  CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER: path.join(tool, 'aarch64-linux-android26-clang'),
  CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS: '-C link-arg=-Wl,-z,max-page-size=16384',
  CMAKE_TOOLCHAIN_FILE_aarch64_linux_android: path.join(root, 'scripts/support/android-media-toolchain.cmake'),
  CMAKE_GENERATOR_aarch64_linux_android: 'Ninja',
};
const output = path.join(root, 'android/app/src/main/jniLibs/arm64-v8a');
const media = path.join(root, '.dart_tool/android-media');
const licenses = path.join(media, 'assets/native-media');
await mkdir(output, { recursive: true });
await rm(licenses, { recursive: true, force: true });
await mkdir(licenses, { recursive: true });
await mkdir(path.join(media, 'engine'), { recursive: true });
const notices = [[path.join(root, 'LICENSE'), 'GPL-3.0.txt'],
  [path.join(root, 'mosh-media/THIRD_PARTY_NOTICES.md'), 'THIRD_PARTY_NOTICES.md']];

await prepareLiveKitWebrtc();
const webrtc = await prepareLibwebrtc(target, { archive });
build({ ...env, LK_CUSTOM_WEBRTC: webrtc });
// A checkout that built the previous engine still has its library here.
await rm(path.join(output, 'libringrtc_rffi.so'), { force: true });
await copyFile(path.join(webrtc, 'libwebrtc.jar'), path.join(media, 'engine/libwebrtc.jar'));
notices.push([path.join(webrtc, 'LICENSE.md'), 'WEBRTC-LICENSE.md']);
await copyFile(path.join(targetRoot, target, 'release/libmosh_native_media.so'),
  path.join(output, 'libmosh_native_media.so'));
for (const [source, name] of notices) await copyFile(source, path.join(licenses, name));
console.log(`android.native.media=${output}`);

function build(buildEnv) {
  // Cargo reads a crate's .cargo/config.toml (link flags) only from its directory.
  const crate = path.join(root, 'mosh-media/webrtc');
  const result = spawnSync('cargo', ['build', '--locked', '--release', '--manifest-path',
    path.join(crate, 'Cargo.toml'), '--target', target, '--target-dir', targetRoot],
  { cwd: crate, env: buildEnv, stdio: 'inherit' });
  if (result.status !== 0) throw new Error(`Android media engine build failed (${result.status})`);
}
