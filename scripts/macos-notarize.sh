#!/usr/bin/env bash
# Notarizes a Developer ID signed DMG and staples the ticket to it, so
# Gatekeeper opens the download without a warning, offline too: opening the
# DMG registers the ticket for the app inside.
#
#   bash scripts/macos-notarize.sh build/macos-dist/Mosh_<version>_universal.dmg
#
# Reads the App Store Connect API key from APP_STORE_CONNECT_ISSUER_ID,
# APP_STORE_CONNECT_KEY_ID and APP_STORE_CONNECT_KEY_P8_BASE64 (repo secrets,
# see CODE_SIGNING.md) and fails without them: scripts/macos-package.sh calls
# it only for builds that must be notarized.
set -euo pipefail

DMG="$1"

fail() {
  echo "error: $*" >&2
  exit 1
}

[ -n "${APP_STORE_CONNECT_KEY_P8_BASE64:-}" ] || fail "APP_STORE_CONNECT_KEY_P8_BASE64 is empty"
[ -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ] || fail "APP_STORE_CONNECT_ISSUER_ID is empty"
[ -n "${APP_STORE_CONNECT_KEY_ID:-}" ] || fail "APP_STORE_CONNECT_KEY_ID is empty"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
KEY="$WORK/AuthKey_$APP_STORE_CONNECT_KEY_ID.p8"
printf '%s' "$APP_STORE_CONNECT_KEY_P8_BASE64" | base64 --decode > "$KEY"
notary() {
  xcrun notarytool "$@" --key "$KEY" --key-id "$APP_STORE_CONNECT_KEY_ID" \
    --issuer "$APP_STORE_CONNECT_ISSUER_ID"
}

# The service usually answers in a few minutes, but a new team's first
# submissions took longer than 30. The timeout keeps a stuck queue from
# holding the runner until the job limit.
notary submit "$DMG" --wait --timeout 60m --output-format json > "$WORK/submission.json" ||
  true
cat "$WORK/submission.json"
status="$(plutil -extract status raw "$WORK/submission.json" 2>/dev/null || true)"
if [ "$status" != "Accepted" ]; then
  id="$(plutil -extract id raw "$WORK/submission.json" 2>/dev/null || true)"
  # The log names each file Apple rejected and why.
  [ -z "$id" ] || notary log "$id" || true
  fail "notarization ended with status '${status:-still in progress at the timeout}'"
fi

xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
# What Gatekeeper checks when a downloaded DMG is opened.
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
