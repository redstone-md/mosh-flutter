#!/usr/bin/env bash
# Archives the iOS app. With the App Store Connect key it exports the archive
# signed for the App Store and, with MOSH_IOS_UPLOAD=true, uploads it to
# TestFlight. Without the key (forks) only the unsigned archive is made:
# proof that the app still builds.
#
#   bash scripts/ios-package.sh
#
# Run after `flutter build ios --config-only`, which writes the build name,
# number and dart defines that the Xcode build reads. The archive is never
# signed: automatic signing there wants a development profile, which needs a
# registered device. The export signs it for distribution instead, with the
# Apple Distribution identity that scripts/apple-import-identity.sh put in
# the keychain (MOSH_SIGN_IDENTITY) and an App Store profile that Xcode
# fetches or creates with the key, so the repo holds no profile
# (CODE_SIGNING.md).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="$ROOT/build/ios/Mosh.xcarchive"
DIST="$ROOT/build/ios-dist"
XCODE=(-workspace "$ROOT/ios/Runner.xcworkspace" -scheme Runner -configuration Release
  -destination generic/platform=iOS -archivePath "$ARCHIVE" -quiet
  # Fixed paths so CI can cache the Rust builds and the Swift packages.
  -derivedDataPath "$ROOT/build/ios/DerivedData" -clonedSourcePackagesDirPath "$ROOT/build/ios/SourcePackages")

fail() {
  echo "error: $*" >&2
  exit 1
}

# The Embed Moss build phase prints nothing under -quiet, so check its
# result: without Moss the app starts but never reaches the network.
check_moss() {
  local moss="$ARCHIVE/Products/Applications/Runner.app/Frameworks/Moss.framework/Moss"
  nm -gU "$moss" | grep -q ' _Moss_Init$' || fail "the app has no Moss.framework exporting Moss_Init"
}

xcodebuild "${XCODE[@]}" CODE_SIGNING_ALLOWED=NO archive
check_moss

if [ -z "${APP_STORE_CONNECT_KEY_P8_BASE64:-}" ]; then
  echo "no App Store Connect key; the archive stays unsigned"
  exit 0
fi
[ -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ] || fail "APP_STORE_CONNECT_ISSUER_ID is empty"
[ -n "${APP_STORE_CONNECT_KEY_ID:-}" ] || fail "APP_STORE_CONNECT_KEY_ID is empty"
[ -n "${APPLE_TEAM_ID:-}" ] || fail "APPLE_TEAM_ID is empty"
# Without a local identity Xcode falls back to cloud-managed certificates,
# which an App Manager key may not use.
[ -n "${MOSH_SIGN_IDENTITY:-}" ] || fail "no Apple Distribution identity was imported"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
KEY="$WORK/AuthKey_$APP_STORE_CONNECT_KEY_ID.p8"
printf '%s' "$APP_STORE_CONNECT_KEY_P8_BASE64" | base64 --decode > "$KEY"
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY"
  -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID")

destination=export
[ "${MOSH_IOS_UPLOAD:-false}" = true ] && destination=upload
cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>$destination</string>
	<key>teamID</key>
	<string>$APPLE_TEAM_ID</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$DIST" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" "${AUTH[@]}"
echo "exported to $DIST ($destination)"
