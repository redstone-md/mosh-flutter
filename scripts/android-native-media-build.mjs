#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { copyFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { prepareAndroidWebRtc } from './android-webrtc-build.mjs';
import { nativeProtoc } from './support/native-protoc.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ndk = process.env.ANDROID_NDK_HOME;
if (!ndk) throw new Error('ANDROID_NDK_HOME is required');
const tool = path.join(ndk, 'toolchains/llvm/prebuilt/linux-x86_64/bin');
const webrtc = await prepareAndroidWebRtc();
const targetRoot = path.join(root, '.dart_tool/native-media/target');
const env = { ...process.env, PROTOC: await nativeProtoc(root),
  MOSH_ANDROID_WEBRTC_DIR: webrtc,
  CC_aarch64_linux_android: path.join(tool, 'aarch64-linux-android26-clang'),
  CXX_aarch64_linux_android: path.join(tool, 'aarch64-linux-android26-clang++'),
  AR_aarch64_linux_android: path.join(tool, 'llvm-ar'),
  CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER: path.join(tool, 'aarch64-linux-android26-clang'),
  CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS: '-C link-arg=-Wl,-z,max-page-size=16384',
  CMAKE_TOOLCHAIN_FILE_aarch64_linux_android: path.join(root, 'scripts/support/android-media-toolchain.cmake'),
  CMAKE_GENERATOR_aarch64_linux_android: 'Ninja',
};
const result = spawnSync('cargo', ['build', '--locked', '--release', '--manifest-path',
  path.join(root, 'mosh-media/engine/Cargo.toml'), '--target', 'aarch64-linux-android',
  '--target-dir', targetRoot], { cwd: root, env, stdio: 'inherit' });
if (result.status !== 0) throw new Error(`Android media engine build failed (${result.status})`);
const output = path.join(root, 'android/app/src/main/jniLibs/arm64-v8a');
await mkdir(output, { recursive: true });
await copyFile(path.join(webrtc, 'libringrtc_rffi.so'), path.join(output, 'libringrtc_rffi.so'));
await copyFile(path.join(targetRoot, 'aarch64-linux-android/release/libmosh_native_media.so'),
  path.join(output, 'libmosh_native_media.so'));
const licenses = path.join(root, '.dart_tool/android-media/assets/native-media');
await mkdir(licenses, { recursive: true });
for (const [source, name] of [[path.join(root, 'LICENSE'), 'GPL-3.0.txt'],
  [path.join(root, 'third_party/ringrtc/LICENSE'), 'AGPL-3.0.txt'],
  [path.join(root, 'mosh-media/THIRD_PARTY_NOTICES.md'), 'THIRD_PARTY_NOTICES.md'],
  [path.join(webrtc, 'LICENSE.md'), 'WEBRTC-LICENSE.md']]) {
  await copyFile(source, path.join(licenses, name));
}
console.log(`android.native.media=${output}`);
