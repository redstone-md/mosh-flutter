// Where the license files of Mosh's Dart packages and Go modules are, for
// license-check.mjs, which audits them, and third-party-licenses.mjs, which
// writes them into the app's notices.
import { execFileSync } from "node:child_process";
import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

/** The contents of a package's license files, by their usual names. */
export function licenseTexts(directory) {
  return readdirSync(directory)
    .filter((name) => /^(LICEN[CS]E|COPYING)/i.test(name) && statSync(path.join(directory, name)).isFile())
    .map((name) => readFileSync(path.join(directory, name), "utf8"));
}

/** Where pub put each package of the app's resolved graph, by name. */
export function dartPackageRoots() {
  const config = JSON.parse(readFileSync(path.join(root, ".dart_tool/package_config.json"), "utf8"));
  return new Map(config.packages.map((entry) => [entry.name,
    fileURLToPath(new URL(entry.rootUri, pathToFileURL(path.join(root, ".dart_tool/"))))]));
}

/**
 * Third-party Go modules in the Moss library Mosh links, each with its
 * module path, version and license files' contents.
 */
export function goModules() {
  const output = execFileSync("go", ["list", "-deps", "-f",
    "{{with .Module}}{{if not .Main}}{{.Path}}@{{.Version}}\t{{.Dir}}{{end}}{{end}}", "./cmd/moss-ffi"],
  { cwd: path.join(root, "moss"), encoding: "utf8" });
  const modules = new Map(output.split("\n").filter(Boolean).map((line) => line.split("\t")));
  return [...modules].map(([module, directory]) => {
    const [name, version] = module.split("@");
    return { id: `go:${module}`, name, version, texts: licenseTexts(directory) };
  });
}
