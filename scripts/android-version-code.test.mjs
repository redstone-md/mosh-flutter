import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { androidVersionCode } from './android-version-code.mjs';

test('the versionCode follows the version, and a pre-release shares it', () => {
  assert.equal(androidVersionCode('name: mosh\nversion: 0.29.0+29000\n'), 29000);
  assert.equal(androidVersionCode('version: 1.2.3-rc.1+1002003\n'), 1002003);
});

test('a missing or mismatched versionCode fails', () => {
  for (const pubspec of ['version: 0.29.0\n', 'version: 0.30.0+29000\n', 'version: 0.1000.0+1000000\n']) {
    assert.throws(() => androidVersionCode(pubspec));
  }
});

test('the committed pubspec.yaml carries its versionCode', async () => {
  androidVersionCode(await readFile(new URL('../pubspec.yaml', import.meta.url), 'utf8'));
});
