#!/usr/bin/env bash
# Archives the iOS app. With the App Store Connect key it signs the archive,
# exports it for the App Store and, with MOSH_IOS_UPLOAD=true, uploads it to
# TestFlight. Without the key (forks) the archive stays unsigned: proof that
# the app still builds.
#
#   bash scripts/ios-package.sh
#
# Run after `flutter build ios --config-only`, which writes the build name,
# number and dart defines that the Xcode build reads. Signing is cloud
# managed: Xcode fetches or creates the certificates and profiles with the
# key, so the repo and the secrets hold no profile (CODE_SIGNING.md).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="$ROOT/build/ios/Mosh.xcarchive"
DIST="$ROOT/build/ios-dist"
XCODE=(-workspace "$ROOT/ios/Runner.xcworkspace" -scheme Runner -configuration Release
  -destination generic/platform=iOS -archivePath "$ARCHIVE" -quiet)

fail() {
  echo "error: $*" >&2
  exit 1
}

if [ -z "${APP_STORE_CONNECT_KEY_P8_BASE64:-}" ]; then
  echo "no App Store Connect key; the archive stays unsigned"
  xcodebuild "${XCODE[@]}" CODE_SIGNING_ALLOWED=NO archive
  exit 0
fi
[ -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ] || fail "APP_STORE_CONNECT_ISSUER_ID is empty"
[ -n "${APP_STORE_CONNECT_KEY_ID:-}" ] || fail "APP_STORE_CONNECT_KEY_ID is empty"
[ -n "${APPLE_TEAM_ID:-}" ] || fail "APPLE_TEAM_ID is empty"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
KEY="$WORK/AuthKey_$APP_STORE_CONNECT_KEY_ID.p8"
printf '%s' "$APP_STORE_CONNECT_KEY_P8_BASE64" | base64 --decode > "$KEY"
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY"
  -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID")

xcodebuild "${XCODE[@]}" "${AUTH[@]}" DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CODE_SIGN_STYLE=Automatic archive

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
