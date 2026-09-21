#!/usr/bin/env bash
# Packages the release macOS app into the shippable DMG.
#
#   node scripts/moss-prepare.mjs && flutter build macos --release
#   bash scripts/macos-package.sh
#   -> build/macos-dist/Mosh_<version>_universal.dmg (+ .sha256)
#
# The DMG is unsigned (ad-hoc app signature): Gatekeeper warns on first
# launch. README documents the official "Open Anyway" flow.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/macos/Build/Products/Release/mosh.app"
VERSION="$(sed -n 's/^version:[[:space:]]*//p' "$ROOT/pubspec.yaml" | tr -d '[:space:]')"
DIST="$ROOT/build/macos-dist"
DMG="$DIST/Mosh_${VERSION}_universal.dmg"
BACKGROUND="$ROOT/macos/packaging/dmg-background.png"

fail() {
  echo "error: $*" >&2
  exit 1
}

# --- Verify the bundle before packaging --------------------------------------
[ -d "$APP" ] || fail "app not found at $APP (run 'flutter build macos --release' first)"
[ -f "$BACKGROUND" ] || fail "DMG background missing at $BACKGROUND"

BUNDLED_LIB="$APP/Contents/MacOS/libmoss.dylib"
[ -f "$BUNDLED_LIB" ] || fail "libmoss.dylib is not in Contents/MacOS (run scripts/moss-prepare.mjs before the build)"

# Everything that must run on both Intel and Apple Silicon: the main
# executable and every dylib in the bundle (mosh_core from cargokit,
# libmoss from the copy phase).
while IFS= read -r -d '' binary; do
  archs="$(lipo -archs "$binary" 2>/dev/null || true)"
  case "$archs" in
    *arm64* | *x86_64*) ;;
    *) fail "unexpected or missing archs '$archs' for $binary" ;;
  esac
  case "$archs" in
    *arm64*) ;;
    *) fail "no arm64 slice in $binary" ;;
  esac
  case "$archs" in
    *x86_64*) ;;
    *) fail "no x86_64 slice in $binary" ;;
  esac
  echo "universal ok: ${binary#"$APP"/} ($archs)"
done < <(find "$APP/Contents/MacOS" "$APP/Contents/Frameworks" -maxdepth 1 \( -name '*.dylib' -o -path "$APP/Contents/MacOS/mosh" \) -print0)

# lipo can damage per-slice ad-hoc signatures; re-sign the dylib ad-hoc
# when verification fails, then the whole bundle must verify. Xcode's
# "Sign to Run Locally" covers everything else at build time.
if ! codesign --verify "$BUNDLED_LIB" >/dev/null 2>&1; then
  echo "re-signing libmoss.dylib ad-hoc (lipo stripped its signature)"
  codesign --force --sign - "$BUNDLED_LIB"
fi

codesign --verify --deep "$APP" || fail "app bundle fails codesign --verify"

# --- DMG ----------------------------------------------------------------------
rm -rf "$DIST"
mkdir -p "$DIST"
rm -f "$DMG"

create-dmg \
  --volname "Mosh" \
  --background "$BACKGROUND" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 128 \
  --icon "mosh.app" 180 190 \
  --app-drop-link 480 190 \
  "$DMG" \
  "$APP"

[ -f "$DMG" ] || fail "create-dmg did not produce $DMG"

# --- Checksum -----------------------------------------------------------------
hash="$(shasum -a 256 "$DMG" | awk '{print $1}')"
echo "$hash  $(basename "$DMG")" > "$DMG.sha256"
echo "$hash  $(basename "$DMG")"
