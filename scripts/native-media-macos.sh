#!/bin/sh
set -eu
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
MOSH_NATIVE_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MOSH_NATIVE_PROFILE=release
if [ "${CONFIGURATION:-Release}" = Debug ]; then MOSH_NATIVE_PROFILE=debug; fi
MOSH_NATIVE_TARGETS=
for MOSH_NATIVE_ARCH in ${ARCHS:-arm64}; do
  case "$MOSH_NATIVE_ARCH" in
    arm64) MOSH_NATIVE_TRIPLE=aarch64-apple-darwin ;;
    x86_64) MOSH_NATIVE_TRIPLE=x86_64-apple-darwin ;;
    *) echo "Unsupported call media architecture: $MOSH_NATIVE_ARCH" >&2; exit 1 ;;
  esac
  MOSH_NATIVE_TARGETS="${MOSH_NATIVE_TARGETS:+$MOSH_NATIVE_TARGETS,}$MOSH_NATIVE_TRIPLE"
done
MOSH_NATIVE_OUTPUT="$DERIVED_FILE_DIR/mosh-native-media"
MACOSX_DEPLOYMENT_TARGET=12.0 node "$MOSH_NATIVE_ROOT/scripts/native-media-build.mjs" \
  --profile "$MOSH_NATIVE_PROFILE" --targets "$MOSH_NATIVE_TARGETS" --output "$MOSH_NATIVE_OUTPUT"
MOSH_NATIVE_APP="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH"
mkdir -p "$MOSH_NATIVE_APP/Frameworks" "$MOSH_NATIVE_APP/Helpers" "$MOSH_NATIVE_APP/Resources/native-media-licenses"
cp "$MOSH_NATIVE_OUTPUT/licenses/"* "$MOSH_NATIVE_APP/Resources/native-media-licenses/"
cp "$MOSH_NATIVE_OUTPUT/libmosh_native_media.dylib" "$MOSH_NATIVE_APP/Frameworks/"
cp "$MOSH_NATIVE_OUTPUT/mosh-camera-capture" "$MOSH_NATIVE_APP/Helpers/"
chmod 755 "$MOSH_NATIVE_APP/Helpers/mosh-camera-capture"
install_name_tool -id '@rpath/libmosh_native_media.dylib' "$MOSH_NATIVE_APP/Frameworks/libmosh_native_media.dylib"
MOSH_NATIVE_SIGNING_IDENTITY=${EXPANDED_CODE_SIGN_IDENTITY:--}
codesign --force --sign "$MOSH_NATIVE_SIGNING_IDENTITY" --options runtime \
  "$MOSH_NATIVE_APP/Frameworks/libmosh_native_media.dylib"
codesign --force --sign "$MOSH_NATIVE_SIGNING_IDENTITY" --options runtime \
  --entitlements "$MOSH_NATIVE_ROOT/mosh-media/capture/macos/Helper.entitlements" \
  "$MOSH_NATIVE_APP/Helpers/mosh-camera-capture"
