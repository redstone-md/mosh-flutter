// Our libwebrtc builds (third_party/libwebrtc-build) by Rust target triple:
// LiveKit's build script and arch, and the directory and archive it yields.
const targets = {
  "x86_64-unknown-linux-gnu": { script: "linux", arch: "x64", directory: "linux-x64-release" },
  "x86_64-pc-windows-msvc": { script: "windows", arch: "x64", directory: "win-x64-release" },
  "aarch64-apple-darwin": { script: "macos", arch: "arm64", directory: "mac-arm64-release" },
  "x86_64-apple-darwin": { script: "macos", arch: "x64", directory: "mac-x64-release" },
  "aarch64-linux-android": { script: "android", arch: "arm64", directory: "android-arm64-release" },
};

/** The build of `triple`, with its release archive name. */
export function libwebrtcTarget(triple) {
  const target = targets[triple];
  if (!target) throw new Error(`No libwebrtc build for ${triple}`);
  return { ...target, archive: `libwebrtc-${target.directory}.tar.gz` };
}
