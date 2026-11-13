#!/usr/bin/env node
// Prints the Android versionCode of the version in pubspec.yaml, the same for
// our release builds and F-Droid's: major * 1000000 + minor * 1000 + patch.
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const version = readFileSync(path.join(root, "pubspec.yaml"), "utf8").match(/^version: (\d+)\.(\d+)\.(\d+)/m);
if (!version) throw new Error("Missing semantic version");
const [major, minor, patch] = version.slice(1).map(Number);
const code = major * 1000000 + minor * 1000 + patch;
if (minor > 999 || patch > 999 || code < 1 || code > 2100000000) throw new Error("Invalid Android versionCode");
console.log(code);
