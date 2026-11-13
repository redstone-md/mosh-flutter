#!/usr/bin/env bash
# Builds Mosh for F-Droid from source: the `prebuild` and `build` steps of
# fdroid/app.mosh.mosh.yml, the draft of its fdroiddata recipe. F-Droid's
# build server runs it with the Flutter and rustup srclibs, the NDK the recipe
# names (Gradle reads it from ANDROID_NDK_HOME) and the Debian packages its
# `sudo` step installs. The APK is unsigned: F-Droid signs it.
#
#   fdroid/build.sh prebuild <flutter srclib> <rustup srclib>
#   fdroid/build.sh build <flutter srclib>
set -euo pipefail
cd "$(dirname "$0")/.."

# The public key that verifies Mosh+ memberships, the MOSH_PLUS_ISSUER_KEY of
# our own builds; the fdroid workflow checks that the two agree. The F-Droid
# build sells no Mosh+ and never contacts the billing server.
PLUS_ISSUER_KEY=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA2rCIa1c9TGzmlloAKF7dqmc1TWVOOzOkfj563g3FE/hU2tyg+engiPhkZ0/IoxTDF13FmXZ48NQiuaA1Tt3JFJwuhe4VJe5hlWcS3JW99AYFDpTzEl1geelrIG6AFOeodujhsJUMXyGbMmwErEHisnAcZGuOGvv4NRWIMUPQxcyBa/EvBnDIYVlruoKIPnMp1MgQvBOm5UGPuZ3pGqjInuFQ7cx2n9Z5d50UZb/fVd1j2vK+3tI7fukC7IsDjhv9byLOfetv27U+IdDa0duEHInTFwDloHgwShX7D7oBhE0LZs929CDI6SGT1UGGWAJjUPjS6UEUCs1qm+1jzFFL+QIDAQAB

step=$1
flutter=$2/bin/flutter
export PATH="$HOME/.cargo/bin:$PATH"

case "$step" in
  prebuild)
    # The flutter srclib is the stable branch; check out the release .fvmrc
    # pins, as our own builds use, so the recipe needs no Flutter version.
    git -C "$2" checkout -f "$(node -p 'JSON.parse(require("fs").readFileSync(".fvmrc", "utf8")).flutter')"
    sh "$3/rustup-init.sh" -y --no-modify-path --profile minimal --default-toolchain none
    # Installs the compiler rust-toolchain.toml pins.
    rustup toolchain install
    rustup target add aarch64-linux-android
    mkdir -p "$HOME/.cargo"
    cat scripts/support/android-cargo-config.toml >> "$HOME/.cargo/config.toml"
    "$flutter" config --no-analytics
    "$flutter" pub get
    node scripts/android-native-hooks-prepare.mjs
    ;;
  build)
    "$flutter" build apk --release --target-platform android-arm64 \
      --split-debug-info=build/android-symbols \
      --dart-define=MOSH_DISTRIBUTION_CHANNEL=fdroid \
      --dart-define=MOSH_PLUS_NETWORK=solana-mainnet \
      "--dart-define=MOSH_PLUS_ISSUER_KEY=$PLUS_ISSUER_KEY" \
      --android-project-arg=moshUnsignedRelease=true
    ;;
  *)
    echo "usage: $0 prebuild <flutter> <rustup> | build <flutter>" >&2
    exit 64
    ;;
esac
