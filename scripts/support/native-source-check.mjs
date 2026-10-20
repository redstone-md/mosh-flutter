import { spawnSync } from 'node:child_process';

/** An expected working patch may be allowed, but staged edits never are. */
export function assertNativeSourceClean(directory, { allowWorkingPatch = false } = {}) {
  const result = spawnSync('git', ['diff', '--quiet', allowWorkingPatch ? '--cached' : 'HEAD', '--'],
    { cwd: directory, encoding: 'utf8' });
  if (result.status !== 0) throw new Error(`Native source has local or staged changes: ${directory}`);
}
