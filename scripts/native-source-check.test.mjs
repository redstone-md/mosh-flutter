import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { assertNativeSourceClean } from './support/native-source-check.mjs';

test('pinned native checkout refuses staged and unstaged source changes', async () => {
  const directory = await mkdtemp(path.join(tmpdir(), 'mosh-native-source-'));
  const git = args => {
    const result = spawnSync('git', args, { cwd: directory, encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
  };
  try {
    git(['init']);
    await writeFile(path.join(directory, 'factory.cc'), 'factory();\n');
    git(['add', 'factory.cc']);
    git(['-c', 'user.name=ForeverInLaw', '-c', 'user.email=44206490+foreverinlaw@users.noreply.github.com',
      'commit', '-m', 'test: source fixture']);
    assertNativeSourceClean(directory);
    await writeFile(path.join(directory, 'factory.cc'), 'changed_factory();\n');
    assert.throws(() => assertNativeSourceClean(directory), /local or staged/);
    assertNativeSourceClean(directory, { allowWorkingPatch: true });
    git(['add', 'factory.cc']);
    assert.throws(() => assertNativeSourceClean(directory), /local or staged/);
    assert.throws(() => assertNativeSourceClean(directory, { allowWorkingPatch: true }), /local or staged/);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
