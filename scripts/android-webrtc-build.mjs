#!/usr/bin/env node
// Build the same pinned WebRTC as desktop, with native Android audio + Moss I/O.
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { copyFile, mkdir, readFile, symlink, writeFile, access } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { prepareRingRtc } from './ringrtc-prepare.mjs';
import { assertNativeSourceClean } from './support/native-source-check.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const patches = path.join(root, 'third_party/webrtc-android-patches');
const output = path.join(root, '.dart_tool/android-media/webrtc');
const checkout = path.join(root, '.dart_tool/android-webrtc');
const depot = path.join(root, '.dart_tool/android-depot-tools');
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const names = ['libringrtc_rffi.so', 'libwebrtc.jar', 'LICENSE.md', 'OPUS-COPYING'];

export async function prepareAndroidWebRtc() {
  if (process.platform !== 'linux') throw new Error('Build Android media on Linux (the release CI uses Ubuntu)');
  await prepareRingRtc();
  const spec = JSON.parse(await readFile(path.join(patches, 'source.json')));
  const inputs = Buffer.concat(await Promise.all([
    'third_party/webrtc-android-patches/source.json',
    'third_party/webrtc-android-patches/mosh.patch',
    'third_party/webrtc-android-patches/args.gn',
    'third_party/ringrtc-patches/source.json',
    'scripts/android-webrtc-build.mjs',
    'scripts/support/native-source-check.mjs',
  ].map(file => readFile(path.join(root, file)))));
  const key = sha(inputs);
  if (await cached(key)) return output;
  const env = { ...process.env, PATH: `${depot}${path.delimiter}${process.env.PATH}`,
    DEPOT_TOOLS_UPDATE: '0', DEPOT_TOOLS_METRICS: '0' };
  const src = await prepareSources(spec, env);
  const build = await compileSources(src, env);
  await cacheProducts(src, build, env, key, spec);
  return output;
}

async function prepareSources(spec, env) {
  await checkoutCommit(depot, 'https://chromium.googlesource.com/chromium/tools/depot_tools.git', spec.depotToolsCommit);
  assertNativeSourceClean(depot);
  await mkdir(checkout, { recursive: true });
  await checkoutCommit(path.join(checkout, 'src'), 'https://github.com/signalapp/webrtc.git', spec.webrtcCommit);
  const config = await Promise.all(['common', 'android'].map(name =>
    readFile(path.join(root, `third_party/ringrtc/config/webrtc.gclient.${name}`))));
  await writeFile(path.join(checkout, '.gclient'), Buffer.concat(config));
  const src = path.join(checkout, 'src');
  assertNativeSourceClean(src, { allowWorkingPatch: true });
  const patch = path.join(patches, 'mosh.patch');
  if (run('git', ['diff', '--quiet'], src, env, true) !== 0) {
    const actual = spawnSync('git', ['diff', '--binary'], { cwd: src, encoding: 'utf8' });
    if (actual.status !== 0 || actual.stdout !== await readFile(patch, 'utf8')) {
      throw new Error('WebRTC contains local source edits');
    }
    run('git', ['apply', '--reverse', patch], src, env);
  }
  run('gclient', ['sync', '--no-history', '--nohooks', '--jobs=8',
    '--revision', `src@${spec.webrtcCommit}`], checkout, env);
  run('gclient', ['recurse', '--jobs=8', '--', 'git', 'diff', '--quiet', 'HEAD', '--'], checkout, env);
  run('git', ['apply', patch], src, env);
  return src;
}

async function compileSources(src, env) {
  const api = path.join(src, 'ringrtc/rffi/api');
  try { await access(api); } catch { await symlink(path.join(root, 'third_party/ringrtc/src/rust/src/webrtc_include'), api); }
  // Production needs tool configuration and Opus models; not test media downloads.
  run('python3', ['build/util/lastchange.py', '-o', 'build/util/LASTCHANGE'], src, env);
  run('python3', ['build/linux/sysroot_scripts/install-sysroot.py', '--arch=amd64'], src, env);
  run('python3', ['build/config/siso/configure_siso.py', '--rbe_instance=',
    '--reapi_backend_config_path=google.star'], src, env);
  run('bash', ['dnn/download_model.sh',
    'a5177ec6fb7d15058e99e57029746100121f68e4890b1467d4094aa336b6013e'],
    path.join(src, 'ringrtc/opus/src'), env);
  const build = path.join(src, 'out/mosh-android-arm64');
  await mkdir(build, { recursive: true });
  await copyFile(path.join(patches, 'args.gn'), path.join(build, 'args.gn'));
  run(path.join(src, 'buildtools/linux64/gn'), ['gen', build], src, env);
  run(path.join(src, 'third_party/siso/cipd/siso'), ['ninja', '-C', build,
    '-offline', '-local_jobs=4', 'ringrtc'], src, env);
  return build;
}

async function cacheProducts(src, build, env, key, spec) {
  await mkdir(output, { recursive: true });
  await copyFile(path.join(build, names[0]), path.join(output, names[0]));
  await copyFile(path.join(build, 'lib.java/sdk/android', names[1]), path.join(output, names[1]));
  run('python3', ['tools_webrtc/libs/generate_licenses.py', '--target', '//ringrtc:ringrtc',
    output, build], src, env);
  await copyFile(path.join(src, 'ringrtc/opus/src/COPYING'), path.join(output, 'OPUS-COPYING'));
  const hashes = Object.fromEntries(await Promise.all(names.map(async name =>
    [name, sha(await readFile(path.join(output, name)))])));
  await writeFile(path.join(output, 'build.json'), JSON.stringify({ key, hashes, ...spec }, null, 2) + '\n');
}

async function cached(key) {
  try {
    const stamp = JSON.parse(await readFile(path.join(output, 'build.json')));
    return stamp.key === key && (await Promise.all(names.map(async name =>
      sha(await readFile(path.join(output, name))) === stamp.hashes[name]))).every(Boolean);
  } catch { return false; }
}

async function checkoutCommit(directory, url, commit) {
  await mkdir(directory, { recursive: true });
  try { await access(path.join(directory, '.git')); }
  catch {
    run('git', ['init', directory]);
    run('git', ['remote', 'add', 'origin', url], directory);
  }
  const head = spawnSync('git', ['rev-parse', 'HEAD'], { cwd: directory, encoding: 'utf8' });
  if (head.stdout.trim() === commit) return;
  run('git', ['fetch', '--depth=1', 'origin', commit], directory);
  run('git', ['checkout', '--detach', commit], directory);
}

function run(command, args, cwd = root, env = process.env, allowFailure = false) {
  const result = spawnSync(command, args, { cwd, env, stdio: 'inherit' });
  if (result.error || (result.status !== 0 && !allowFailure)) throw new Error(`${command} failed (${result.status}): ${result.error ?? ''}`);
  return result.status;
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  console.log(`android.webrtc=${await prepareAndroidWebRtc()}`);
}
