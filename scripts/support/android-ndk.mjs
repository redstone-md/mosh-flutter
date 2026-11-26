// The Android NDK's LLVM toolchain on this build host. The NDK ships one
// prebuilt per host OS (the darwin one is universal despite its name). On
// Windows the target-prefixed clang wrappers are .cmd scripts, which a
// process spawn finds only by their full name.
import path from "node:path";

const hostTags = { win32: "windows-x86_64", linux: "linux-x86_64", darwin: "darwin-x86_64" };

/** The prebuilt directory name for `platform`, e.g. "linux-x86_64". */
export function ndkHostTag(platform = process.platform) {
  const tag = hostTags[platform];
  if (!tag) throw new Error(`Unsupported NDK host platform: ${platform}`);
  return tag;
}

/** Clang, clang++ and llvm-ar of the NDK at `ndkRoot` for `triple` at API `api`. */
export function ndkToolchain(ndkRoot, { triple, api }, platform = process.platform) {
  const bin = path.join(ndkRoot, "toolchains", "llvm", "prebuilt", ndkHostTag(platform), "bin");
  const [script, executable] = platform === "win32" ? [".cmd", ".exe"] : ["", ""];
  return {
    cc: path.join(bin, `${triple}${api}-clang${script}`),
    cxx: path.join(bin, `${triple}${api}-clang++${script}`),
    ar: path.join(bin, `llvm-ar${executable}`),
  };
}
