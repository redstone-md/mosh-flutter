#!/bin/sh
# Xcode build phase of the iOS Runner target: builds Moss and the call engine
# for the device and embeds them into the app's Frameworks folder as
# Moss.framework and MoshMedia.framework, signed with the app's identity.
# mosh-core dlopens both from there (MOSS_LIBRARY_NAME, native_call/library.rs).
#
# Device builds only: Go builds ios/arm64 against the iPhoneOS SDK, our
# libwebrtc is built for devices, and there is no simulator slice yet.
set -eu

if [ "${PLATFORM_NAME:-}" != "iphoneos" ]; then
  echo "error: Moss and the call engine are built for iPhone devices only, not ${PLATFORM_NAME:-unknown}" >&2
  exit 1
fi

# Xcode starts build phases with a minimal PATH; node, go and cargo usually
# live in these.
PATH="$PATH:$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:/usr/local/go/bin"

PROFILE=release
if [ "${CONFIGURATION:-Release}" = Debug ]; then PROFILE=debug; fi
MEDIA="$DERIVED_FILE_DIR/mosh-native-media"

cd "$SRCROOT/.."
node scripts/moss-prepare-ios.mjs
# Cargo also builds build scripts for the Mac: like cargokit, keep Xcode's
# iPhoneOS SDKROOT and toolchain PATH away from them. The iOS target finds
# its SDK through xcrun.
(
  unset SDKROOT
  PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v 'Contents/Developer/' | paste -sd: -)"
  node scripts/native-media-build.mjs --profile "$PROFILE" --targets aarch64-apple-ios --output "$MEDIA"
)

APP="$TARGET_BUILD_DIR/$WRAPPER_NAME"
DEST="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
mkdir -p "$DEST" "$APP/native-media-licenses"
rm -rf "$DEST/Moss.framework" "$DEST/MoshMedia.framework"
cp -R moss-runtime/ios/Moss.framework "$MEDIA/MoshMedia.framework" "$DEST/"
cp "$MEDIA/licenses/"* "$APP/native-media-licenses/"

if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${CODE_SIGNING_REQUIRED:-YES}" != "NO" ]; then
  for framework in Moss MoshMedia; do
    codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none "$DEST/$framework.framework"
  done
fi
