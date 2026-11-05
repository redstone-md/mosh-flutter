#!/usr/bin/env node
// Builds the packaged call engine (MOSH_CALL_ENGINE, see
// scripts/support/call-engine.mjs) for Android arm64 into jniLibs, with its
// libwebrtc Java classes and license notices.
import { spawnSync } from 'node:child_process';
import { copyFile, mkdir, rm } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { prepareAndroidWebRtc } from './android-webrtc-build.mjs';
import { prepareLibwebrtc, prepareLiveKitWebrtc } from './livekit-webrtc-prepare.mjs';
import { callEngine } from './support/call-engine.mjs';
import { nativeProtoc } from './support/native-protoc.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ndk = process.env.ANDROID_NDK_HOME;
if (!ndk) throw new Error('ANDROID_NDK_HOME is required');
const target = 'aarch64-linux-android';
const engineName = process.env.MOSH_CALL_ENGINE || 'ringrtc';
const engine = callEngine(engineName);
const tool = path.join(ndk, 'toolchains/llvm/prebuilt/linux-x86_64/bin');
const targetRoot = path.join(root, '.dart_tool/native-media', engine.targetDirectory);
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
await mkdir(path.join(media, `engine-${engineName}`), { recursive: true });
const notices = [[path.join(root, 'LICENSE'), 'GPL-3.0.txt'],
  [path.join(root, 'mosh-media/THIRD_PARTY_NOTICES.md'), 'THIRD_PARTY_NOTICES.md']];

if (engineName === 'webrtc') {
  await prepareLiveKitWebrtc();
  const webrtc = await prepareLibwebrtc(target);
  build({ ...env, LK_CUSTOM_WEBRTC: webrtc });
  // RingRTC's libwebrtc must not linger beside this engine from an earlier build.
  await rm(path.join(output, 'libringrtc_rffi.so'), { force: true });
  await copyFile(path.join(webrtc, 'libwebrtc.jar'), path.join(media, `engine-${engineName}`, 'libwebrtc.jar'));
  notices.push([path.join(webrtc, 'LICENSE.md'), 'WEBRTC-LICENSE.md']);
} else {
  const webrtc = await prepareAndroidWebRtc();
  build({ ...env, MOSH_ANDROID_WEBRTC_DIR: webrtc });
  await copyFile(path.join(webrtc, 'libringrtc_rffi.so'), path.join(output, 'libringrtc_rffi.so'));
  await copyFile(path.join(webrtc, 'libwebrtc.jar'), path.join(media, `engine-${engineName}`, 'libwebrtc.jar'));
  notices.push([path.join(root, 'third_party/ringrtc/LICENSE'), 'AGPL-3.0.txt'],
    [path.join(webrtc, 'LICENSE.md'), 'WEBRTC-LICENSE.md'],
    [path.join(webrtc, 'OPUS-COPYING'), 'OPUS-COPYING']);
}
await copyFile(path.join(targetRoot, target, 'release/libmosh_native_media.so'),
  path.join(output, 'libmosh_native_media.so'));
for (const [source, name] of notices) await copyFile(source, path.join(licenses, name));
console.log(`android.native.media=${output}`);

function build(buildEnv) {
  // Cargo reads a crate's .cargo/config.toml (link flags) only from its directory.
  const crate = path.join(root, 'mosh-media', engine.crate);
  const result = spawnSync('cargo', ['build', '--locked', '--release', '--manifest-path',
    path.join(crate, 'Cargo.toml'), '--target', target, '--target-dir', targetRoot],
  { cwd: crate, env: buildEnv, stdio: 'inherit' });
  if (result.status !== 0) throw new Error(`Android media engine build failed (${result.status})`);
}
