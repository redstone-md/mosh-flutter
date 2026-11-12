#!/usr/bin/env node
// Checks the licenses of the Dart packages and Go modules every Mosh build
// ships; cargo-deny (deny.toml) checks the Rust crates. Mosh is GPL-3.0 with
// an app store exception that covers only its own code, so a GPL, LGPL or
// AGPL dependency, or one without a recognisable license, fails the check
// until docs/licenses.md records a decision and REVIEWED below names it.
import { execFileSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { dartPackageRoots, goModules, licenseTexts } from "./support/license-sources.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

/**
 * Package versions decided by hand; docs/licenses.md has the reasoning. Any
 * other version is audited again.
 */
const REVIEWED = new Map([
  ["go:github.com/anacrolix/multiless@v0.3.1-0.20221221005021-2d12701f83f7",
    "MPL-2.0 since v0.4.0; this commit predates its LICENCE"],
  ["go:github.com/anacrolix/sync@v0.4.0", "MPL-2.0 since v0.5.0; v0.4.0 predates its LICENCE"],
]);

/** Path packages of this repository, under the root LICENSE. */
const OWN_DART_PACKAGES = new Set(["mosh_core"]);

// Strongest first. The GPL family is matched by its upper-case titles, which
// MPL-2.0 does not contain although it names those licenses in its text.
const LICENSES = [
  ["AGPL", /GNU AFFERO GENERAL PUBLIC LICENSE/],
  ["LGPL", /GNU (LESSER|LIBRARY) GENERAL PUBLIC LICENSE/],
  ["GPL", /GNU GENERAL PUBLIC LICENSE/],
  ["MPL-2.0", /Mozilla Public License,? version 2\.0/i],
  ["Apache-2.0", /Apache License,?\s+Version 2\.0/i],
  ["BSD", /Redistribution and use in source and binary forms/i],
  ["MIT", /Permission is hereby granted, free of charge/i],
  ["ISC", /Permission to use, copy, modify, and\/or distribute/i],
  ["Zlib", /altered source versions must be plainly marked/i],
];
const COPYLEFT = new Set(["AGPL", "LGPL", "GPL"]);

const identify = (text) => LICENSES.find(([, pattern]) => pattern.test(text))?.[0];

/**
 * Problems with `packages`, each `{ id, texts }` where id is
 * "<ecosystem>:<name>@<version>" and texts its license files' contents.
 */
export function audit(packages) {
  return packages.flatMap(({ id, texts }) => {
    if (REVIEWED.has(id)) return [];
    if (!texts.length) return [`${id}: no license file`];
    const licenses = texts.map(identify);
    if (licenses.includes(undefined)) return [`${id}: license not recognised`];
    const copyleft = licenses.find((license) => COPYLEFT.has(license));
    return copyleft ? [`${id}: ${copyleft} is not allowed without a review`] : [];
  });
}

/**
 * Components of a libwebrtc build's generated LICENSE.md that store builds
 * must not contain: anything under the GPL family, and the H.264 codecs our
 * builds leave out (`rtc_use_h264=false`).
 */
export function disallowedSections(notices) {
  return notices.split(/^# /m).slice(1).flatMap((section) => {
    const [name] = section.split("\n", 1);
    const copyleft = /GNU (Affero |Lesser |Library )?General Public License/i.test(section)
      && !/Mozilla Public License/i.test(section);
    return copyleft || /^(ffmpeg|openh264|x264)$/i.test(name.trim()) ? [name.trim()] : [];
  });
}

/**
 * The app's non-dev Dart packages, ours excluded. The Flutter SDK's own
 * packages bundle their notices; the hosted packages they use are checked.
 */
function dartPackages() {
  const output = execFileSync("flutter", ["pub", "deps", "--json"], { cwd: root, encoding: "utf8" });
  const { packages } = JSON.parse(output.slice(output.indexOf("{")));
  const byName = new Map(packages.map((entry) => [entry.name, entry]));
  const roots = dartPackageRoots();
  const appRoot = packages.find((entry) => entry.kind === "root");
  const seen = new Set();
  const pending = appRoot.dependencies.filter((name) => !appRoot.devDependencies.includes(name));
  while (pending.length) {
    const entry = byName.get(pending.pop());
    if (seen.has(entry)) continue;
    seen.add(entry);
    pending.push(...entry.dependencies);
  }
  return [...seen].filter((entry) => entry.source !== "sdk" && !OWN_DART_PACKAGES.has(entry.name))
    .map(({ name, version }) => ({ id: `dart:${name}@${version}`, texts: licenseTexts(roots.get(name)) }));
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const packages = [...dartPackages(), ...goModules()];
  const problems = audit(packages);
  for (const problem of problems) console.error(`license-check: ${problem}`);
  console.log(`license-check: ${packages.length} Dart packages and Go modules, ${problems.length} problems`);
  if (problems.length) process.exitCode = 1;
}
