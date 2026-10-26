# Android release builds

Mosh's Android APK targets **arm64-v8a, Android 8.0 (API 26) or newer**.
The package id remains `app.mosh.mosh`. Physical-device acceptance is separate
from successful compilation and package verification.

## Build and distribution

`build-android.yml` is the shared signed release build for main CI, manual CI
runs and future tagged releases. PRs keep the existing unsigned-development
debug build and never invoke the signing workflow. Both modes reuse
`android-build-setup` for the pinned Flutter, JDK, Rust, Moss and Opus preparation.
No new runtime dependencies or protocol changes are needed.
Native compiler caches are saved immediately after compilation, so a later
package-validation failure does not discard expensive reusable build outputs.

The workflow requires repository secrets `ANDROID_KEYSTORE_BASE64` and
`ANDROID_KEYSTORE_PASSWORD`, with alias `mosh` and the same alphanumeric store/key
password. It restores the key and ignored `android/key.properties` privately on
the runner, then removes both in an `always()` cleanup step. Release signing
never falls back to Android's debug key. Debug builds do not require these secrets.
Keep an independent private backup: GitHub does not return stored secret values.
An explicit `preReleaseBuild` guard also prevents Gradle's unsigned-APK fallback
when signing properties are incomplete. CI temporarily removes the properties
and requires this exact failure, then restores them before package verification.

Repository variable `ANDROID_SIGNING_CERT_SHA256` independently pins the
signing certificate. Production `MOSH_PLUS_SERVER_URL` and `MOSH_PLUS_ISSUER_KEY`
variables are mandatory; the existing compiled AOT probe verifies the same
configuration factory used by the app. No billing private keys enter the build.

Initial release certificate SHA-256:
`e79117cfc5fc330108cb6656a905e5bbefc7d411981bdd406b18aa27d71ee0cf`.

The release uses Flutter AOT, default R8 shrinking, the committed Rust release
profile and `--target-platform android-arm64`. Dart symbols and R8 mappings are
uploaded separately as `mosh-android-symbols`. APKs contain no debug entry point.
The Android version code is `major * 1000000 + minor * 1000 + patch` (minor/patch
at most 999); preview rebuilds keep that version code and the same signing key.
An update can replace an equal-version APK. Published stable versions increase it.
Flutter prepopulates all supported ABIs in `defaultConfig`; Mosh explicitly clears
that set before selecting ARM64, following the
[Flutter migration guide](https://docs.flutter.dev/release/breaking-changes/default-abi-filters-android).
Adding ARM64 to the default set alone incorrectly packaged third-party ARM32/x86
libraries without matching Mosh libraries; final package checks reject that case.

`android-package-verify.sh` checks the final APK with Android SDK tools:

- valid signature matching the independent certificate pin;
- production package id, API 26 minimum and no debuggable manifest flag;
- exactly one ABI, including real Flutter, app, Rust and Moss libraries;
- every native LOAD segment and the APK ZIP support 16 KiB page alignment;
- JNI Zero's native-only Java entry points and exact method signatures survive
  shrinking in the final DEX, including `JniZero.init` and `CommonApis` callbacks;
- Mosh's initialization, network-change and transfer-execution JNI signatures
  match the exported entry points in the packaged Rust library.

The matching WebRTC JAR includes JNI Zero without Chromium's consumer keep
rules. The application therefore preserves
`CalledByNative`, `CalledByNativeUnchecked` and `AccessedByNative` members using
the pinned upstream rule pattern. Without these rules R8 removed `JniZero`,
causing `ClassNotFoundException` and a fatal abort in RingRTC's `JNI_OnLoad`.
`android-jni-verify.py` inspects actual DEX definitions and static signatures;
finding a class in the input JAR or in arbitrary APK strings is insufficient.

The prior main APK exposed 4 KiB LOAD alignment in `libmoss.so` and the
irondash native hook. The Moss wrapper now supplies explicit 16 KiB external
linker flags. Shared CI preparation installs the target-scoped settings from
`scripts/support/android-cargo-config.toml` into the runner's Cargo configuration.
Dart hooks filter Cargo environment variables, so merely exporting Rust flags
does not reach the independent irondash build. This does not patch either upstream
source tree. For local Android builds, merge that target table into
`~/.cargo/config.toml`; clean old hook outputs before rebuilding.

The `mosh-android-release` artifact contains the APK, SHA-256 sidecar and
`plus-build.json` with source commit and public billing configuration. Tagged
releases publish those files beside the Windows and macOS installers.

## Installation and acceptance

The Activity initializes CPAL's JVM/application context before starting Dart.
A process-lifetime global application reference survives Activity recreation;
an Activity itself is never retained. `node scripts/android-context-check.mjs`
exercises the production JNI entry point with a real host JVM, including a
missing context, repeat initialization and garbage collection. This checks
ownership/bootstrap, not Android hardware enumeration or playback.

Gradle also builds the pinned RingRTC/WebRTC engine for native Android ↔ desktop
audio/video, stages both shared libraries and uses the Java API from the same
build. The APK verifier requires those libraries and checks their LOAD segments.
CI caches the small checksummed WebRTC products; a cache miss builds its pinned
source/dependency graph locally without remote-execution credentials.

For calls, test both directions against Windows/macOS with both apps foreground:
voice, video, camera off/on, front/back selection, denied camera permission,
output routing, and hang-up/retry. Android Back first closes a device dialog,
then minimizes the call view; another Back returns a DM to its list. Background
or killed-app ringing and Bluetooth routing are separate physical checks.

Download the APK to the phone, permit installation from the downloading app
when Android requests it, then install. Existing debug-signed Mosh installations
cannot update to this release signature. **Do not uninstall a used installation
without protecting access to its account/history first:** uninstalling erases its
private data. Use another phone/profile or arrange device linking before migration.
Future release APKs use the same signing key and update in place.

First verify cold launch, unlock, Settings → Profile → Mosh+, then link the phone
through Settings → Devices. Keep both devices online through initial sync.
Verify a real mainnet payment, badge synchronization and a restart separately;
the build result alone establishes none of those outcomes. Network fees require
SOL in the paying wallet. Wallet recovery restores purchases, not chat history.

Payment QR instructions currently assume a second camera device; there is no
same-phone wallet launch button in checkout yet. For acceptance, display the
payment QR on the desktop and pay with the phone wallet. Actual wallet
compatibility remains part of acceptance.

See [linked Android text DM](android-linked-dm.md) for foreground messaging limits
and [mainnet acceptance](plus-mainnet-ru.md) for the payment checklist.
