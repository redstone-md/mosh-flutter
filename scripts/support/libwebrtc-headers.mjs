// The headers webrtc-sys compiles against, out of the whole WebRTC tree that
// LiveKit's build scripts copy into a libwebrtc archive (every *.h and *.inc,
// about 600 MB unpacked). From webrtc-sys's own sources it follows each
// #include through the include directories its build.rs passes, on every
// branch of every #if, so the set holds for every platform and flag. The
// hermetic libc++ trees stay whole: their headers have no extension.
import { readdir, readFile, rm, rmdir } from 'node:fs/promises';
import path from 'node:path';

const INCLUDE = /^[ \t]*#[ \t]*(?:include|import)[ \t]*[<"]([^>"\n]+)[>"]/gm;
const SOURCE = /\.(?:c|cc|cpp|h|hpp|inc|mm)$/;
const PRUNED = /\.(?:h|inc)$/;
// The include directories of third_party/webrtc-sys/build.rs, under include/.
const SEARCH = [
  '',
  'third_party/abseil-cpp',
  'third_party/libyuv/include',
  'third_party/libc++',
  'third_party/libc++/src/include',
  'third_party/libc++abi/src/include',
  'buildtools/third_party/libc++',
  'sdk/objc',
  'sdk/objc/base',
];
const WHOLE = ['third_party/libc++/', 'third_party/libc++abi/', 'buildtools/third_party/libc++/'];

/**
 * Deletes the *.h and *.inc files under `include` (an archive's include/
 * directory) that no source of `webrtcSys` reaches, and the directories that
 * leaves empty. Returns how many headers it kept and removed.
 */
export async function pruneHeaders(include, webrtcSys) {
  const used = await usedHeaders(include, webrtcSys);
  let kept = 0;
  let removed = 0;
  for (const file of await files(include)) {
    if (!PRUNED.test(file) || used.has(file) || isWhole(include, file)) {
      kept += PRUNED.test(file) ? 1 : 0;
      continue;
    }
    await rm(file);
    removed += 1;
  }
  await removeEmptyDirectories(include);
  return { kept, removed };
}

/** The files under `include` that the sources of `webrtcSys` include, directly or not. */
export async function usedHeaders(include, webrtcSys) {
  const roots = [];
  for (const directory of ['src', 'include']) {
    roots.push(...(await files(path.join(webrtcSys, directory))).filter((file) => SOURCE.test(file)));
  }
  const searchDirectories = [
    ...SEARCH.map((directory) => path.join(include, directory)),
    path.join(webrtcSys, 'include'),
  ];
  const seen = new Set(roots);
  const pending = [...roots];
  while (pending.length) {
    const file = pending.pop();
    for (const name of includedNames(await readFile(file, 'utf8'))) {
      const found = await resolve(name, [path.dirname(file), ...searchDirectories]);
      if (found && !seen.has(found)) {
        seen.add(found);
        pending.push(found);
      }
    }
  }
  return new Set([...seen].filter((file) => file.startsWith(include + path.sep)));
}

const includedNames = (text) => [...text.matchAll(INCLUDE)].map((match) => match[1].trim());

// The first directory that has `name`, as the compiler searches them.
async function resolve(name, directories) {
  for (const directory of directories) {
    const candidate = path.join(directory, name);
    if (await isFile(candidate)) return candidate;
  }
  return null;
}

const fileCache = new Map();
function isFile(file) {
  if (!fileCache.has(file)) {
    fileCache.set(file, readFile(file).then(() => true, () => false));
  }
  return fileCache.get(file);
}

const isWhole = (include, file) =>
  WHOLE.some((prefix) => path.relative(include, file).split(path.sep).join('/').startsWith(prefix));

async function files(directory) {
  const entries = await readdir(directory, { recursive: true, withFileTypes: true }).catch(() => []);
  return entries.filter((entry) => entry.isFile()).map((entry) => path.join(entry.parentPath, entry.name));
}

async function removeEmptyDirectories(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  let empty = true;
  for (const entry of entries) {
    if (!entry.isDirectory()) {
      empty = false;
      continue;
    }
    const child = path.join(directory, entry.name);
    if (await removeEmptyDirectories(child)) await rmdir(child);
    else empty = false;
  }
  return empty;
}
