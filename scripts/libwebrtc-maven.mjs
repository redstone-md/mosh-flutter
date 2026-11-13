#!/usr/bin/env node
// Publishes our libwebrtc build for Android to Maven Central, where F-Droid
// accepts it from and the Android build fetches it (android/app/build.gradle.kts).
// The archive is the GitHub release asset .github/workflows/libwebrtc.yml
// built; this checks it against build.json, signs the files with the GPG key
// imported beforehand and uploads them through the Central Portal API.
//
//   MAVEN_CENTRAL_USERNAME, MAVEN_CENTRAL_PASSWORD: a Central Portal user token
//   MAVEN_GPG_PASSPHRASE: the passphrase of the signing key
//   node scripts/libwebrtc-maven.mjs --archive libwebrtc-android-arm64-release.tar.gz
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { parseArgs } from "node:util";
import { setTimeout as sleep } from "node:timers/promises";
import { libwebrtcSpec } from "./livekit-webrtc-prepare.mjs";
import { libwebrtcTarget } from "./support/libwebrtc-targets.mjs";

const PORTAL = "https://central.sonatype.com/api/v1/publisher";
const REPOSITORY = "https://repo1.maven.org/maven2";
const ANDROID = libwebrtcTarget("aarch64-linux-android");

/** The Maven coordinates of the Android build of `spec`'s release. */
export function coordinates(spec) {
  const [group, artifact] = spec.maven.split(":");
  const version = spec.release.replace(/^libwebrtc-/, "");
  return { group, artifact, version, directory: `${group.replaceAll(".", "/")}/${artifact}/${version}` };
}

/**
 * The files of the Maven Central bundle, by path: the POM and the archive
 * under the classifier Gradle asks for, each with its MD5 and SHA-1. The GPG
 * signatures are added when publishing.
 */
export function bundle(spec, archive) {
  const { artifact, version, directory } = coordinates(spec);
  const base = `${directory}/${artifact}-${version}`;
  const files = new Map([[`${base}.pom`, Buffer.from(pom(spec))], [`${base}-${ANDROID.directory}.tar.gz`, archive]]);
  for (const [file, bytes] of [...files]) {
    for (const algorithm of ["md5", "sha1"]) files.set(`${file}.${algorithm}`, Buffer.from(hash(algorithm, bytes)));
  }
  return files;
}

function pom(spec) {
  const { group, artifact, version } = coordinates(spec);
  const source = "https://github.com/redstone-md/mosh-flutter";
  return `<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>${group}</groupId>
  <artifactId>${artifact}</artifactId>
  <version>${version}</version>
  <packaging>pom</packaging>
  <name>libwebrtc for Mosh</name>
  <description>Google's libwebrtc from LiveKit's webrtc-sdk fork at ${spec.commit}, built without H.264 by LiveKit's scripts for Mosh's call engine. The ${ANDROID.directory} archive holds the static library, its headers, the Java classes and the licenses of everything in it (LICENSE.md).</description>
  <url>${source}</url>
  <licenses>
    <license>
      <name>BSD-3-Clause</name>
      <url>https://webrtc.googlesource.com/src/+/refs/heads/main/LICENSE</url>
    </license>
  </licenses>
  <developers>
    <developer>
      <id>redstone-md</id>
      <name>Redstone</name>
      <url>https://github.com/redstone-md</url>
    </developer>
  </developers>
  <scm>
    <connection>scm:git:${source}.git</connection>
    <url>${source}/blob/main/.github/workflows/libwebrtc.yml</url>
  </scm>
</project>
`;
}

const hash = (algorithm, bytes) => createHash(algorithm).update(bytes).digest("hex");

async function published(spec) {
  const { artifact, version, directory } = coordinates(spec);
  const response = await fetch(`${REPOSITORY}/${directory}/${artifact}-${version}.pom`, { method: "HEAD" });
  if (response.ok) return true;
  if (response.status === 404) return false;
  throw new Error(`Maven Central answered ${response.status}`);
}

/** Writes and signs the bundle, and zips it the way the Portal reads it. */
async function bundleZip(spec, archive, directory) {
  const contents = path.join(directory, "bundle");
  for (const [file, bytes] of bundle(spec, archive)) {
    await mkdir(path.dirname(path.join(contents, file)), { recursive: true });
    await writeFile(path.join(contents, file), bytes);
    if (/\.(md5|sha1)$/.test(file)) continue;
    run("gpg", ["--batch", "--yes", "--pinentry-mode", "loopback", "--passphrase-fd", "0",
      "--armor", "--detach-sign", file], contents, process.env.MAVEN_GPG_PASSPHRASE);
  }
  run("zip", ["-q", "-r", "../bundle.zip", "."], contents);
  return path.join(directory, "bundle.zip");
}

async function portal(endpoint, body) {
  const token = Buffer.from(`${process.env.MAVEN_CENTRAL_USERNAME}:${process.env.MAVEN_CENTRAL_PASSWORD}`);
  const response = await fetch(`${PORTAL}/${endpoint}`, {
    method: "POST", headers: { Authorization: `Bearer ${token.toString("base64")}` }, body,
  });
  if (!response.ok) throw new Error(`Central Portal ${endpoint}: ${response.status} ${await response.text()}`);
  return response;
}

/** Uploads the bundle for automatic publishing and waits until Maven Central has it. */
async function publish(spec, zip) {
  const form = new FormData();
  form.append("bundle", new Blob([await readFile(zip)]), "bundle.zip");
  const name = encodeURIComponent(`${spec.maven}:${coordinates(spec).version}`);
  const id = (await (await portal(`upload?publishingType=AUTOMATIC&name=${name}`, form)).text()).trim();
  console.log(`Central Portal deployment ${id}`);
  for (let minute = 0; minute < 60; minute++) {
    const status = await (await portal(`status?id=${id}`)).json();
    if (status.deploymentState === "PUBLISHED") return;
    if (status.deploymentState === "FAILED") throw new Error(`deployment failed: ${JSON.stringify(status.errors)}`);
    console.log(status.deploymentState);
    await sleep(60_000);
  }
  throw new Error(`deployment ${id} is not published after an hour`);
}

function run(command, args, cwd, input) {
  const result = spawnSync(command, args, { cwd, input, stdio: [input === undefined ? "ignore" : "pipe", "inherit", "inherit"] });
  if (result.status !== 0) throw new Error(`${command} failed (${result.status ?? result.error?.message})`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const { values } = parseArgs({ options: { archive: { type: "string" } } });
  if (!values.archive) throw new Error("--archive <libwebrtc-android-arm64-release.tar.gz> is required");
  const spec = await libwebrtcSpec();
  const { group, artifact, version } = coordinates(spec);
  if (await published(spec)) {
    console.log(`${group}:${artifact}:${version} is on Maven Central already`);
  } else {
    const archive = await readFile(values.archive);
    if (hash("sha256", archive) !== spec.archives[ANDROID.directory]) {
      throw new Error(`${values.archive} is not the ${ANDROID.archive} pinned for ${spec.release}`);
    }
    const directory = await mkdtemp(path.join(tmpdir(), "libwebrtc-maven-"));
    try {
      await publish(spec, await bundleZip(spec, archive, directory));
      console.log(`${group}:${artifact}:${version} published`);
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  }
}
