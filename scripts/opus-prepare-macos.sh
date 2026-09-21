#!/usr/bin/env bash
# opus-prepare-macos.sh -- builds the universal (arm64 + x86_64) libopus.a
# audiopus_sys links against when mosh-core is built on macOS.
#
# audiopus_sys-0.1.8's build.rs cannot cross-compile opus itself (its
# configure run has no --host), so the x86_64 slice of a universal release
# build has no opus to link. rust_builder/macos/mosh_core.podspec therefore
# points LIBOPUS_LIB_DIR at third_party/opus-macos-universal (gitignored:
# a build artifact) and expects the library to be there -- the same shape
# as scripts/opus-prepare-android.sh + the cargokit gradle plugin use for
# Android. On a Mac this script builds it, from the opus source vendored
# inside the audiopus_sys crate.
#
# Output: third_party/opus-macos-universal/libopus.a + include/opus*.h
# Needs: cargo, Xcode clang, autoconf/automake/libtool.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/third_party/opus-macos-universal"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || nproc)"

# Objects built without a floor claim the SDK default (26.x), and every
# link against them warns about newer-minimum objects; 12.0 is the
# channel's documented floor (the Go 1.25 runtime's).
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-12.0}"

# The crate vendors the opus source; fetching the crate is how we get it.
cargo fetch --manifest-path "$ROOT/mosh-core/Cargo.toml"
SRC="$(ls -d "${CARGO_HOME:-$HOME/.cargo}"/registry/src/*/audiopus_sys-0.1.8/opus | head -n1)"
[ -d "$SRC" ] || { echo "vendored opus source not found under the cargo registry" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# One configure/make per slice; Apple's clang crosses with -arch, and
# --host tells autoconf it is a cross build (so it does not run test
# binaries compiled for the other arch).
for arch in arm64 x86_64; do
  case "$arch" in
    arm64) host=aarch64-apple-darwin ;;
    x86_64) host=x86_64-apple-darwin ;;
  esac

  cp -r "$SRC" "$WORK/$arch"
  (
    cd "$WORK/$arch"
    ./autogen.sh
    ./configure \
      --host="$host" \
      CC="clang -arch $arch" \
      AR=ar RANLIB=ranlib \
      --enable-static --disable-shared \
      --disable-doc --disable-extra-programs --with-pic
    make -j"$JOBS"
  )
done

mkdir -p "$OUT/include"
lipo -create \
  -output "$OUT/libopus.a" \
  "$WORK/arm64/.libs/libopus.a" \
  "$WORK/x86_64/.libs/libopus.a"
cp "$WORK/arm64/include/opus"*.h "$OUT/include/"
echo "opus.macos.universal=$OUT/libopus.a"
