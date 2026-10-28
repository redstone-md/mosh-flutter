#!/usr/bin/env bash
# Verify the final signed APK, including every bundled native library.
set -euo pipefail
APK="${1:?Usage: android-package-verify.sh <release.apk>}"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:?Set ANDROID_HOME or ANDROID_SDK_ROOT}}"
PIN="${ANDROID_SIGNING_CERT_SHA256:?Set the independent signing certificate SHA-256}"
PIN="${PIN//:/}"
PIN="${PIN,,}"
[[ "$PIN" =~ ^[0-9a-f]{64}$ ]] || { echo 'Invalid Android signing certificate SHA-256' >&2; exit 1; }
TOOLS="$(find "$SDK/build-tools" -name apksigner -type f | sort -V | tail -n1)"
TOOLS="$(dirname "$TOOLS")"
NDK="$(find -L "$SDK/ndk" -name llvm-readelf -type f | sort -V | tail -n1)"
test -x "$NDK" || { echo 'Android NDK llvm-readelf is missing or not executable' >&2; exit 1; }
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

"$TOOLS/apksigner" verify --verbose --print-certs "$APK" | tee "$WORK/signature.txt"
actual="$(sed -n 's/^.*certificate SHA-256 digest: //p' "$WORK/signature.txt" | sort -u)"
test "$actual" = "$PIN"
grep -qx 'Number of signers: 1' "$WORK/signature.txt"

"$TOOLS/aapt" dump badging "$APK" > "$WORK/manifest.txt"
grep "^package: name='app.mosh.mosh'" "$WORK/manifest.txt"
grep "^sdkVersion:'26'" "$WORK/manifest.txt"
grep '^native-code:' "$WORK/manifest.txt"
grep -qx "native-code: 'arm64-v8a'" "$WORK/manifest.txt"
if grep -q '^application-debuggable' "$WORK/manifest.txt"; then
  echo 'Release APK must not be debuggable' >&2
  exit 1
fi

unzip -q "$APK" 'lib/*' -d "$WORK"
unzip -p "$APK" assets/native-media/WEBRTC-LICENSE.md > "$WORK/webrtc-license.txt"
test -s "$WORK/webrtc-license.txt"
test "$(find "$WORK/lib" -mindepth 1 -maxdepth 1 -type d | wc -l)" = 1
for library in libapp.so libflutter.so libmosh_core.so libmoss.so libmosh_native_media.so libringrtc_rffi.so; do
  test -s "$WORK/lib/arm64-v8a/$library"
done

"$NDK" --dyn-syms --wide "$WORK/lib/arm64-v8a/libmosh_core.so" > "$WORK/core-symbols.txt"
for method in initialize notifyNetworkChanged setTransferExecution setTransferInteractive; do
  if ! awk '$7 != "UND" {print $8}' "$WORK/core-symbols.txt" |
    grep -x "Java_app_mosh_mosh_MoshNative_$method" > /dev/null; then
    echo "Missing Android native entry point: MoshNative.$method" >&2
    exit 1
  fi
done

for library in "$WORK"/lib/arm64-v8a/*.so; do
  "$NDK" --program-headers --wide "$library" > "$WORK/headers.txt"
  # Android 15+ can use 16 KiB pages: every LOAD segment must support them.
  grep -q '^[[:space:]]*LOAD ' "$WORK/headers.txt"
  while read -r alignment; do
    if (( alignment < 16384 )); then
      echo "Native library lacks 16 KiB alignment: $(basename "$library")" >&2
      exit 1
    fi
  done < <(awk '/^[[:space:]]*LOAD / { print $NF }' "$WORK/headers.txt")
done
"$TOOLS/zipalign" -c -P 16 4 "$APK"
python3 "$(dirname "$0")/android-jni-verify.py" "$APK" --dexdump "$TOOLS/dexdump"
python3 - "$APK" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as apk:
    for direction in ("incoming", "outgoing"):
        name = f"assets/flutter_assets/assets/audio/ringtone_{direction}.wav"
        info = apk.getinfo(name)
        assert info.compress_type == zipfile.ZIP_STORED, f"MediaPlayer needs an uncompressed asset: {name}"
        assert apk.read(name)[:4] == b"RIFF", f"Invalid ringtone asset: {name}"
print("Android ringtone recordings are packaged for native MediaPlayer playback.")
PY
echo 'Android release signature, manifest, arm64 native libraries and 16 KiB alignment verified.'
