#!/usr/bin/env bash
# opus-prepare-android.sh -- builds the arm64 libopus.a audiopus_sys links
# against when mosh-core is cross-compiled for Android, on a Linux host.
#
# audiopus_sys-0.1.8's build.rs cannot cross-compile opus itself (its
# configure run has no --host), so rust_builder/cargokit/gradle/plugin.gradle
# points LIBOPUS_LIB_DIR at third_party/opus-android-arm64 and expects the
# library to be there. On Windows, third_party/build-opus-android.ps1 makes
# it; this is the Linux counterpart CI uses, built from the same vendored
# opus source (the one inside the audiopus_sys crate) with the NDK clang.
#
# Output: third_party/opus-android-arm64/libopus.a + include/opus*.h
# Needs: ANDROID_NDK_HOME, cargo, autoconf/automake/libtool.
set -euo pipefail

API="${OPUS_ANDROID_API:-24}"
NDK="${ANDROID_NDK_HOME:?ANDROID_NDK_HOME is not set}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/third_party/opus-android-arm64"
TOOL="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"

# The crate vendors the opus source; fetching the crate is how we get it.
cargo fetch --manifest-path "$ROOT/mosh-core/Cargo.toml"
SRC="$(ls -d "${CARGO_HOME:-$HOME/.cargo}"/registry/src/*/audiopus_sys-0.1.8/opus | head -n1)"
[ -d "$SRC" ] || { echo "vendored opus source not found under the cargo registry" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp -r "$SRC" "$WORK/opus"
cd "$WORK/opus"

./autogen.sh
./configure \
  --host=aarch64-linux-android \
  CC="$TOOL/aarch64-linux-android${API}-clang" \
  AR="$TOOL/llvm-ar" \
  RANLIB="$TOOL/llvm-ranlib" \
  --enable-static --disable-shared \
  --disable-doc --disable-extra-programs --with-pic
make -j"$(nproc)"

mkdir -p "$OUT/include"
cp .libs/libopus.a "$OUT/"
cp include/opus*.h "$OUT/include/"
echo "opus.android.arm64=$OUT/libopus.a"
