#!/usr/bin/env node
// pubspec.yaml carries the Android versionCode after the version
// (`version: 1.2.3+1002003`), where Flutter builds and F-Droid's update check
// read it. The code is major * 1000000 + minor * 1000 + patch, so a
// pre-release and its release share one. Prints the code, or fails when it
// disagrees with the version.
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

/** The versionCode pubspec.yaml declares, checked against its version. */
export function androidVersionCode(pubspec) {
  const match = /^version:\s*(\d+)\.(\d+)\.(\d+)(?:-[^+\s]+)?\+(\d+)\s*$/m.exec(pubspec);
  if (!match) throw new Error('pubspec.yaml version must look like 1.2.3+1002003');
  const [major, minor, patch, declared] = match.slice(1).map(Number);
  const code = major * 1000000 + minor * 1000 + patch;
  if (minor > 999 || patch > 999 || code < 1 || code > 2100000000) throw new Error('Invalid Android versionCode');
  if (declared !== code) throw new Error(`pubspec.yaml declares versionCode ${declared}, its version needs ${code}`);
  return code;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  console.log(androidVersionCode(await readFile(new URL('../pubspec.yaml', import.meta.url), 'utf8')));
}
