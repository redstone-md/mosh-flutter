#!/usr/bin/env node
import { createHash } from "node:crypto";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

// media_kit_libs_windows_video downloads libmpv and ANGLE at CMake time with
// one unretried file(DOWNLOAD); a truncated download fails the whole Windows
// build ("Integrity check failed"). CMake skips its download when the archive
// already sits in its binary dir with the right MD5, so fetch them here with
// retries first. URLs and MD5s are read from the plugin's own CMakeLists, so
// a plugin bump cannot drift from this script.
//
// Run after `flutter pub get` from the repo root. Usage:
//   node scripts/media-kit-prefetch.mjs [dest=build/windows/x64]

const PLUGIN = "media_kit_libs_windows_video";
const ARCHIVES = ["LIBMPV", "ANGLE"];
const ATTEMPTS = 4;
const DEST = path.resolve(process.argv[2] ?? "build/windows/x64");

const cmake = await readFile(await pluginCMakeLists(), "utf8");
await mkdir(DEST, { recursive: true });
for (const name of ARCHIVES) {
  await fetchVerified(archiveSpec(cmake, name));
}

// The plugin's windows/CMakeLists.txt, located through package_config.json.
async function pluginCMakeLists() {
  const config = JSON.parse(
    await readFile(".dart_tool/package_config.json", "utf8"),
  );
  const pkg = config.packages.find((p) => p.name === PLUGIN);
  if (!pkg) fail(`${PLUGIN} is not in package_config.json; run flutter pub get`);
  const root = new URL(pkg.rootUri, pathToFileURL(path.resolve(".dart_tool") + path.sep));
  return path.join(fileURLToPath(root), "windows", "CMakeLists.txt");
}

// { file, url, md5 } for one `set(NAME ...)` / `set(NAME_URL ...)` /
// `set(NAME_MD5 ...)` triple in the plugin's CMakeLists.
function archiveSpec(text, name) {
  const read = (key) => {
    const match = text.match(new RegExp(`set\\(${key} "([^"]+)"\\)`));
    if (!match) fail(`set(${key} ...) not found in ${PLUGIN}'s CMakeLists`);
    return match[1];
  };
  const file = read(name);
  return {
    file,
    url: read(`${name}_URL`).replace(`\${${name}}`, file),
    md5: read(`${name}_MD5`),
  };
}

async function fetchVerified({ file, url, md5 }) {
  const target = path.join(DEST, file);
  if (md5Of(await readFile(target).catch(() => null)) === md5) {
    console.log(`${file}: cached, MD5 ok`);
    return;
  }
  for (let attempt = 1; attempt <= ATTEMPTS; attempt++) {
    try {
      const response = await fetch(url);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const body = Buffer.from(await response.arrayBuffer());
      const got = md5Of(body);
      if (got !== md5) throw new Error(`MD5 ${got}, want ${md5}`);
      await writeFile(target, body);
      console.log(`${file}: downloaded, MD5 ok (attempt ${attempt})`);
      return;
    } catch (error) {
      console.warn(`${file}: attempt ${attempt}/${ATTEMPTS} failed: ${error.message}`);
      await rm(target, { force: true });
      if (attempt < ATTEMPTS) await sleep(attempt * 5000);
    }
  }
  fail(`${file}: no verified download after ${ATTEMPTS} attempts from ${url}`);
}

function md5Of(buffer) {
  return buffer && createHash("md5").update(buffer).digest("hex");
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
