#!/bin/sh
# Xcode build phase of the iOS Runner target: builds Moss for the device and
# embeds Moss.framework into the app's Frameworks folder, signed with the
# app's identity. mosh-core dlopens it from there (MOSS_LIBRARY_NAME).
#
# Device builds only: Go builds ios/arm64 against the iPhoneOS SDK, and there
# is no simulator slice yet.
set -eu

if [ "${PLATFORM_NAME:-}" != "iphoneos" ]; then
  echo "error: Moss is built for iPhone devices only, not ${PLATFORM_NAME:-unknown}" >&2
  exit 1
fi

# Xcode starts build phases with a minimal PATH; node and go usually live in
# Homebrew's prefix.
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/local/go/bin"

cd "$SRCROOT/.."
node scripts/moss-prepare-ios.mjs

DEST="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
mkdir -p "$DEST"
rm -rf "$DEST/Moss.framework"
cp -R moss-runtime/ios/Moss.framework "$DEST/"

if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${CODE_SIGNING_REQUIRED:-YES}" != "NO" ]; then
  codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none "$DEST/Moss.framework"
fi
