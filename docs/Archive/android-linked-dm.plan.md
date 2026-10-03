# Android linked text DM, issue 28

Baseline: `68488c3dd6959181de11c62b30543a63f9840dae` on `main`.
Spec: https://github.com/redstone-md/mosh-flutter/issues/28.

## Scope and decisions

- Reuse the approved device roster, per-installation signing/Moss/MLS keys,
  encrypted history, admission, recovery and revocation from issues 23–27.
- Keep the Android Keystore DEK and app-private data directory startup order.
  Cold starts reopen the installation; linking never copies another DEK or
  private identity. Exclude installation data from Android backup/transfer.
- Declare network access in the main manifest so release builds can use Moss.
- Pause Android UI polling while hidden/paused and refresh immediately when
  resumed. Retain the native runtime and existing per-kind in-flight guards.
  Desktop polling keeps its existing behavior.
- Use device-neutral linking copy in the existing Settings section. A phone
  shows its QR; the desktop imports the screenshot or private link and the
  human confirms the phone's code. No camera dependency or new pairing flow.
- Add a real Android bridge test plus a host runner using the existing native
  installation workers. A loopback HTTP control connection through adb reverse
  coordinates tests only; all messenger traffic uses automatic real Moss
  discovery. Run cold-start phases in separate Android processes without
  clearing installation data. Use a separate test application id.
- No new dependencies, Rust bridge operations, record schemas or Moss changes.

## Confirmed test boundaries

The user confirmed on 2026-09-28: existing Android DEK/startup, Riverpod and UI
foreground-return behavior, real bridge/Moss across Android and two desktop
installations. Use focused red/green tests at these boundaries.

## Checks

- Focused foreground/DEK/widget tests while implementing; `flutter analyze`.
- Build Android arm64 with the real prepared Moss library and NDK.
- Host-controlled physical scenario: confirmed QR, initial history, independent
  identity after cold launch, text while the original desktop is off, concurrent
  sends, Android foreground return/reconnect, desktop recovery without duplicate
  ids, and revocation before future text/sync.
- Existing real desktop device-link and multi-device DM scenarios; full Flutter
  and Rust suites once at the end; Dart/Rust formatting and strict Clippy.
- Review the final diff against the baseline for standards and issue coverage,
  fix findings, then atomic Conventional Commit on the current branch.

## Risks and verification limits

The user has a physical arm64 phone but cannot connect it to this server.
Provide a runnable local-host scenario and record physical results as unrun.
An emulator or Linux worker is not physical Android evidence. Android background
delivery, push, iOS, other conversation kinds and media remain separate work.
Moss requires an available authorized holder for recovery; device roster fork
merging remains outside this slice. Test-only data must never replace a real
phone installation or log QR secrets.

## Verification recorded on 2026-09-28

- Full Flutter suite: 881 passed, 5 existing skips. Focused foreground tests:
  8 passed, including hidden/resumed transitions, a read held across resume,
  desktop behavior and mounting while paused.
- Flutter analysis and Dart formatting passed. Production-file coverage:
  `foreground_poller.dart` 100% lines/branches, `auto_poll_provider.dart` 100%,
  `device_link_provider.dart` 27/29 lines and 19/21 branches.
- Normal debug arm64 APK and the isolated integration APK built with actual
  Rust and Moss libraries. The manifest declares Internet access and excludes
  installation backup/transfer. No phone was attached to this server.
- Existing real desktop Devices UI scenario passed. The shared real DM UI
  scenario passed both process phases after the review fixes: confirmed
  independent installation, rendered history, concurrent sends, composer sends
  with the original off, contact reconnection, desktop recovery, same identity
  after cold start, missed text and revocation with retained history.
- Rust unit suite: 410 passed, 11 ignored. Integration suites: 28 passed,
  2 ignored, one existing test failed when a worker's Moss socket bind returned
  `-13`. That test passed alone on retry. Rust formatting, strict Clippy and
  doc tests passed. No Rust API or generated bindings changed.
- Mermaid rendering passed for Architecture and the new ADR/feature guide.
- Standards review: 0 remaining findings. Spec review: 0 remaining code
  findings. Fixes cover partial-resource cleanup, real DM UI refresh/sends,
  contact interruption and stable Riverpod overrides between test screens.

Physical arm64 acceptance and a manual release-APK flow remain unrun.
The local-host command and evidence checklist are in
[the Android feature guide](../Features/android-linked-dm.md).

## Changed files

- `android-linked-dm.plan.md`
- `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/res/xml/data_extraction_rules.xml`
- `docs/ADR/0034-android-linked-text-dm.md`
- `docs/Architecture.md`
- `docs/Features/android-linked-dm.md`
- `docs/Features/device-linking.md`
- `integration_test/android_linked_dm_test.dart`
- `integration_test/support/linked_dm_control.dart`
- `integration_test/support/linked_dm_scenario.dart`
- `integration_test/support/linked_dm_test.dart`
- `integration_test/support/linked_dm_ui.dart`
- `lib/l10n/app_en.arb`
- `lib/l10n/app_ru.arb`
- `lib/src/features/device_link/device_link_provider.dart`
- `lib/src/platform/foreground_poller.dart`
- `lib/src/state/auto_poll_provider.dart`
- `native_test/android_linked_dm_test.dart`
- `native_test/device_link_test.dart`
- `native_test/support/native_peer.dart`
- `scripts/android_linked_dm.dart`
- `scripts/support/linked_dm_fixture.dart`
- `test/features/conversation/dm_revoked_screen_test.dart`
- `test/state/auto_poll_provider_test.dart`
