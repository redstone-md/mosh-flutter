import assert from 'node:assert/strict';
import { mkdir, mkdtemp, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { pruneHeaders } from './support/libwebrtc-headers.mjs';

async function tree(root, files) {
  for (const [file, text] of Object.entries(files)) {
    await mkdir(path.dirname(path.join(root, file)), { recursive: true });
    await writeFile(path.join(root, file), text);
  }
}

async function list(directory) {
  const entries = await readdir(directory, { recursive: true, withFileTypes: true });
  return entries.filter((entry) => entry.isFile())
    .map((entry) => path.relative(directory, path.join(entry.parentPath, entry.name)).split(path.sep).join('/'))
    .sort();
}

test('the archive keeps the headers webrtc-sys reaches, on every platform branch', async (t) => {
  const root = await mkdtemp(path.join(tmpdir(), 'libwebrtc-headers-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const include = path.join(root, 'archive/include');
  const webrtcSys = path.join(root, 'webrtc-sys');
  await tree(webrtcSys, {
    'src/peer.cpp': '#include "livekit/peer.h"\n#include <vector>\n',
    'src/mac.mm': '#import "sdk/objc/base/RTCMacros.h"\n',
    'include/livekit/peer.h': '#pragma once\n#include "api/peer.h"\n',
  });
  await tree(include, {
    'api/peer.h': '#if defined(WEBRTC_WIN)\n#include "rtc_base/win.h"\n#else\n#include "rtc_base/posix.h"\n#endif\n'
      + '#include "absl/strings/string_view.h"\n#include "tables.inc"\n',
    'api/tables.inc': '',
    'api/unused.h': '',
    'rtc_base/win.h': '',
    'rtc_base/posix.h': '',
    'third_party/abseil-cpp/absl/strings/string_view.h': '',
    'third_party/tflite/model.h': '',
    'sdk/objc/base/RTCMacros.h': '',
    'third_party/libc++/src/include/__config.h': '',
    'build/linux/sysroot/usr/include/stdio.h': '',
  });
  await writeFile(path.join(root, 'archive/webrtc.ninja'), 'defines = -DWEBRTC_POSIX\n');

  assert.deepEqual(await pruneHeaders(include, webrtcSys), { kept: 7, removed: 3 });
  assert.deepEqual(await list(path.join(root, 'archive')), [
    'include/api/peer.h',
    'include/api/tables.inc',
    'include/rtc_base/posix.h',
    'include/rtc_base/win.h',
    'include/sdk/objc/base/RTCMacros.h',
    'include/third_party/abseil-cpp/absl/strings/string_view.h',
    'include/third_party/libc++/src/include/__config.h',
    'webrtc.ninja',
  ]);
});
