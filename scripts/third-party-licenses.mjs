#!/usr/bin/env node
// Writes assets/licenses/NOTICES: the licenses of what Mosh ships beyond its
// Dart packages, whose notices Flutter collects itself. That is Mosh's own
// license, the Rust crates of mosh-core and the media crates (from their
// Cargo.lock, through cargo-about), the Go modules of Moss, libmpv and FFmpeg
// under the LGPL with the sources of the builds media_kit downloads, and the
// Inter font. The app adds the file to its license page
// (lib/src/app/bundled_licenses.dart). CI writes it again and fails when the
// committed file differs: run this script after changing a dependency.
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { dartPackageRoots, goModules } from "./support/license-sources.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const OUTPUT = "assets/licenses/NOTICES";

/** The Rust code Mosh ships; deny.toml checks the same crates. */
const RUST_CRATES = ["mosh-core", "mosh-media/webrtc", "mosh-media/capture"];

/**
 * The libmpv builds media_kit downloads, read from the plugin versions
 * pubspec.lock pins. Linux uses the system's libmpv and Android has none
 * (docs/licenses.md).
 */
const LIBMPV_BUILDS = [
  { platform: "Windows", plugin: "media_kit_libs_windows_video", file: "windows/CMakeLists.txt",
    license: "third_party/licenses/LGPL-3.0.txt" },
  { platform: "macOS", plugin: "media_kit_libs_macos_video", file: "macos/Makefile",
    license: "third_party/licenses/LGPL-2.1.txt" },
  { platform: "iOS", plugin: "media_kit_libs_ios_video", file: "ios/Makefile",
    license: "third_party/licenses/LGPL-2.1.txt" },
];

/** Splits entries, as in Flutter's own NOTICES. */
const SEPARATOR = `\n${"-".repeat(80)}\n`;

/**
 * The file's text: one entry per distinct license text, naming every
 * component under it, in the format Flutter's license registry reads.
 */
export function notices(components) {
  const byText = new Map();
  for (const { names, text } of components) {
    const normalized = text.replace(/\r\n/g, "\n").trimEnd();
    if (normalized.includes(SEPARATOR.trim())) {
      throw new Error(`${names.join(", ")}: the license text contains the entry separator`);
    }
    const entry = byText.get(normalized) ?? new Set();
    names.forEach((name) => entry.add(name));
    byText.set(normalized, entry);
  }
  return `${[...byText]
    .map(([text, names]) => `${[...names].sort().join("\n")}\n\n${text}`)
    .sort()
    .join(SEPARATOR)}\n`;
}

/** The release page of the libmpv build a media_kit plugin's build file downloads. */
export function libmpvRelease(buildFile) {
  const variables = new Map([...buildFile.matchAll(/^(\w+)=(\S+)$/gm)].map(([, name, value]) => [name, value]));
  const expanded = buildFile.replace(/\$\{(\w+)\}/g, (reference, name) => variables.get(name) ?? reference);
  const match = expanded.match(/https:\/\/github\.com\/([\w.-]+\/libmpv-[\w.-]+)\/releases\/download\/([\w.-]+)\//);
  if (!match) throw new Error("no libmpv release download in the build file");
  return `https://github.com/${match[1]}/releases/tag/${match[2]}`;
}

const read = (file) => readFileSync(path.join(root, file), "utf8");

/** cargo-about accepts what deny.toml allows, so one list governs both. */
function aboutConfig(directory) {
  const allow = read("deny.toml").match(/^allow = \[([^\]]*)\]/m)[1];
  const accepted = [...allow.matchAll(/"([^"]+)"/g)].map(([, id]) => id);
  const file = path.join(directory, "about.toml");
  writeFileSync(file, [
    `accepted = ${JSON.stringify(accepted)}`,
    "ignore-dev-dependencies = true",
    "no-clearly-defined = true",
    "private = { ignore = true }",
    "",
  ].join("\n"));
  return file;
}

function rustCrates() {
  const directory = mkdtempSync(path.join(tmpdir(), "mosh-licenses-"));
  try {
    const config = aboutConfig(directory);
    return RUST_CRATES.flatMap((crate) => {
      const output = path.join(directory, "about.json");
      // cargo-about logs every SPDX comment it cannot parse in crate sources;
      // its output is shown only when it fails.
      execFileSync("cargo", ["about", "generate", "--manifest-path", path.join(crate, "Cargo.toml"),
        "--config", config, "--all-features", "--format", "json", "--output-file", output],
      { cwd: root, stdio: "pipe" });
      return JSON.parse(readFileSync(output, "utf8")).licenses.map(({ text, used_by: usedBy }) => ({
        names: usedBy.map(({ crate }) => crate.name), text,
      }));
    });
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

function mossModules() {
  return goModules().map(({ name, version, texts }) => ({
    names: [name],
    text: texts.length ? texts.join("\n\n")
      : `This version has no license file. Its source: https://pkg.go.dev/${name}@${version}`,
  }));
}

/** libmpv and FFmpeg, one entry per LGPL version, with each build's sources. */
function libmpv() {
  const plugins = dartPackageRoots();
  const licenses = [...new Set(LIBMPV_BUILDS.map(({ license }) => license))];
  return licenses.map((license) => {
    const sources = LIBMPV_BUILDS.filter((build) => build.license === license)
      .map(({ platform, plugin, file }) =>
        `${platform}: ${libmpvRelease(readFileSync(path.join(plugins.get(plugin), file), "utf8"))}`);
    return {
      names: ["FFmpeg", "libmpv"],
      text: [
        "Mosh links libmpv and FFmpeg dynamically under the GNU Lesser General Public License. "
          + "The release of each build it ships, with the build scripts that name the mpv and FFmpeg sources:",
        sources.join("\n"),
        read(license),
      ].join("\n\n"),
    };
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const components = [
    { names: ["Mosh"], text: read("LICENSE") },
    { names: ["Inter"], text: read("assets/fonts/Inter-OFL.txt") },
    ...rustCrates(),
    ...mossModules(),
    ...libmpv(),
  ];
  writeFileSync(path.join(root, OUTPUT), notices(components));
  console.log(`third-party-licenses: ${components.length} license texts written to ${OUTPUT}`);
}
