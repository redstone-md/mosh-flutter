import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { chmod, mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { withSourceLock } from "./source-lock.mjs";

const artifacts = {
  "linux-x64": ["linux-x86_64", "121f6c7afe1d4d0e3ea6aab9432038599250134cbf4474cb1167d2c7decd4278"],
  "linux-arm64": ["linux-aarch_64", "8b8f18bd2b30346efbc698dd5a73dd7c805f3ef8380f6dfc95c768f3f1852f6a"],
  "darwin-x64": ["osx-universal_binary", "83d0dc80672f53486f54299bca6177159f9cad1fd54d4d3143eeea53c4423e1b"],
  "darwin-arm64": ["osx-universal_binary", "83d0dc80672f53486f54299bca6177159f9cad1fd54d4d3143eeea53c4423e1b"],
  "win32-x64": ["win64", "f0c128dc0d8492eceece83bb459a4c0e316764b929ffbf1aa416357fd644edd3"],
};

/** Prefer an explicit/system compiler; otherwise provision a verified local tool. */
export async function nativeProtoc(root) {
  for (const candidate of [process.env.PROTOC, "protoc"].filter(Boolean)) {
    if (spawnSync(candidate, ["--version"], { windowsHide: true }).status === 0) return candidate;
  }
  const spec = artifacts[`${process.platform}-${process.arch}`];
  if (!spec) throw new Error("Install protoc for this host or set PROTOC");
  const directory = path.join(root, ".dart_tool/native-tools", `protoc-36.2-${spec[0]}`);
  return withSourceLock(`${directory}.lock`, async () => {
    await mkdir(directory, { recursive: true });
    const compiler = path.join(directory, "bin", process.platform === "win32" ? "protoc.exe" : "protoc");
    if (spawnSync(compiler, ["--version"], { windowsHide: true }).status === 0) return compiler;
    const name = `protoc-36.2-${spec[0]}.zip`;
    const archive = path.join(directory, name);
    let bytes = await readFile(archive).catch(() => null);
    if (!bytes || hash(bytes) !== spec[1]) {
      const response = await fetch(`https://github.com/protocolbuffers/protobuf/releases/download/v36.2/${name}`,
        { signal: AbortSignal.timeout(60_000) });
      if (!response.ok) throw new Error(`protoc download failed: ${response.status}`);
      bytes = Buffer.from(await response.arrayBuffer());
      if (hash(bytes) !== spec[1]) throw new Error("protoc archive checksum mismatch");
      await writeFile(archive, bytes);
    }
    const command = process.platform === "darwin" ? "/usr/bin/ditto" : process.platform === "win32"
      ? path.join(process.env.SystemRoot ?? "C:\\Windows", "System32", "tar.exe") : "unzip";
    const args = process.platform === "darwin" ? ["-xk", name, "."]
      : process.platform === "win32" ? ["-xf", name] : ["-o", "-q", name];
    const extracted = spawnSync(command, args, { cwd: directory, stdio: "inherit", windowsHide: true });
    if (extracted.status !== 0) throw new Error("Cannot extract protoc; install unzip or set PROTOC");
    if (process.platform !== "win32") await chmod(compiler, 0o755);
    if (spawnSync(compiler, ["--version"], { windowsHide: true }).status !== 0) throw new Error("protoc validation failed");
    return compiler;
  });
}
const hash = (bytes) => createHash("sha256").update(bytes).digest("hex");
