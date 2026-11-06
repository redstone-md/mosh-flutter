#!/usr/bin/env node
// Checks the licenses of the Dart packages and Go modules every Mosh build
// ships; cargo-deny (deny.toml) checks the Rust crates. Mosh is GPL-3.0 with
// an app store exception that covers only its own code, so a GPL, LGPL or
// AGPL dependency, or one without a recognisable license, fails the check
// until docs/licenses.md records a decision and REVIEWED below names it.
import { execFileSync } from "node:child_process";
import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

/** Packages decided by hand; docs/licenses.md has the reasoning. */
const REVIEWED = new Map([
  ["go:github.com/anacrolix/multiless", "MPL-2.0 since v0.4.0; the pinned commit predates its LICENCE"],
  ["go:github.com/anacrolix/sync", "MPL-2.0 since v0.5.0; v0.4.0 predates its LICENCE"],
]);

// Most specific first: MPL-2.0 quotes the GPL family's names in its own text.
const LICENSES = [
  ["MPL-2.0", /^\s*Mozilla Public License,? version 2\.0/i],
  ["AGPL", /GNU AFFERO GENERAL PUBLIC LICENSE/i],
  ["LGPL", /GNU (LESSER|LIBRARY) GENERAL PUBLIC LICENSE/i],
  ["GPL", /GNU GENERAL PUBLIC LICENSE/i],
  ["Apache-2.0", /Apache License,?\s+Version 2\.0/i],
  ["BSD", /Redistribution and use in source and binary forms/i],
  ["MIT", /Permission is hereby granted, free of charge/i],
  ["ISC", /Permission to use, copy, modify, and\/or distribute/i],
  ["Zlib", /altered source versions must be plainly marked/i],
];
const COPYLEFT = new Set(["AGPL", "LGPL", "GPL"]);

const identify = (text) => LICENSES.find(([, pattern]) => pattern.test(text))?.[0];

/**
 * Problems with `packages`, each `{ id, text }` where id is
 * "<ecosystem>:<name>" and text the license file, or null without one.
 */
export function audit(packages) {
  return packages.flatMap(({ id, text }) => {
    if (REVIEWED.has(id)) return [];
    if (text === null) return [`${id}: no license file`];
    const license = identify(text);
    if (!license) return [`${id}: license not recognised`];
    return COPYLEFT.has(license) ? [`${id}: ${license} is not allowed without a review`] : [];
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

function licenseText(directory) {
  const file = readdirSync(directory).find((name) => /^(LICEN[CS]E|COPYING)/i.test(name)
    && statSync(path.join(directory, name)).isFile());
  return file ? readFileSync(path.join(directory, file), "utf8") : null;
}

/** The app's non-dev Dart packages outside the Flutter SDK, ours excluded. */
function dartPackages() {
  const output = execFileSync("flutter", ["pub", "deps", "--json"], { cwd: root, encoding: "utf8" });
  const { packages } = JSON.parse(output.slice(output.indexOf("{")));
  const byName = new Map(packages.map((entry) => [entry.name, entry]));
  const config = JSON.parse(readFileSync(path.join(root, ".dart_tool/package_config.json"), "utf8"));
  const roots = new Map(config.packages.map((entry) => [entry.name,
    fileURLToPath(new URL(entry.rootUri, pathToFileURL(path.join(root, ".dart_tool/"))))]));
  const appRoot = packages.find((entry) => entry.kind === "root");
  const seen = new Set();
  const pending = appRoot.dependencies.filter((name) => !appRoot.devDependencies.includes(name));
  while (pending.length) {
    const entry = byName.get(pending.pop());
    if (seen.has(entry.name) || entry.source === "sdk" || entry.name === "mosh_core") continue;
    seen.add(entry.name);
    pending.push(...entry.dependencies);
  }
  return [...seen].map((name) => ({ id: `dart:${name}`, text: licenseText(roots.get(name)) }));
}

/** Third-party Go modules in the Moss library Mosh links. */
function goModules() {
  const output = execFileSync("go", ["list", "-deps", "-f",
    "{{with .Module}}{{if not .Main}}{{.Path}}\t{{.Dir}}{{end}}{{end}}", "./cmd/moss-ffi"],
  { cwd: path.join(root, "moss"), encoding: "utf8" });
  const modules = new Map(output.split("\n").filter(Boolean).map((line) => line.split("\t")));
  return [...modules].map(([name, directory]) => ({ id: `go:${name}`, text: licenseText(directory) }));
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const packages = [...dartPackages(), ...goModules()];
  const problems = audit(packages);
  for (const problem of problems) console.error(`license-check: ${problem}`);
  console.log(`license-check: ${packages.length} Dart packages and Go modules, ${problems.length} problems`);
  if (problems.length) process.exitCode = 1;
}
