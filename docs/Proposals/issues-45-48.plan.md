# Composer and interface language

Approved scope: GitHub issues #48 and #45. Message deletion, chat renaming and
video calls remain separate requests.

## Work

1. Reproduce focus loss and consecutive keyboard sends in all conversation kinds.
   Keep the composer editable, capture each submitted draft immediately and admit
   text sends in order. Preserve separate failed submissions and existing native
   message delivery states. Completion must not clear a newer draft or steal focus.
2. Add System, Russian and English to Profile settings using the existing selector.
   Persist only the explicit interface-language preference, independently of setup.
   Let Flutter resolve system locales and follow OS changes; English is the fallback.
3. Translate the existing macOS menu labels without replacing their Cocoa actions
   or shortcuts. OS-owned services and dialogs retain the OS's own localization.

## Risks and checks

- Exercise held sends, identical bodies, failures, retry, navigation/disposal and
  revoked input. Native admission stays ordered; delivery remains native-owned.
- Exercise saved language on restart, missing/invalid preferences, failed writes,
  live system-language changes and responsive settings.
- Run formatting, Flutter analysis and the full widget suite with coverage.
  Measure changed executable lines and branches against the repository gates.
- Native macOS menu behavior needs the macOS build lane or a physical Mac; the
  development host is Linux. Verify Dart channel payloads and native menu mappings.
- Keep dependencies, Rust bridge and existing persistence schemas unchanged.

Use verified Conventional Commits per issue. Published as
[PR #52](https://github.com/redstone-md/mosh-flutter/pull/52) after approval.

## Verification (2026-10-04)

- `dart format lib test integration_test`: 520 Dart files formatted.
- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --branch-coverage`: 1370 passed, 5 existing native-library
  tests skipped on this host. Keyboard submission cases run for Windows, Linux,
  macOS, Android and iOS using Flutter platform variants.
- The four updated onboarding test files were rerun after their final formatting
  and async-call updates: 100 passed.
- Changed executable Dart code against `956ff5f`: 239/244 lines (98.0%) and 84/89
  branches (94.4%) covered. Generated localization code is outside this diff.
- `git diff --check` and `actionlint .github/workflows/build-macos.yml`: passed.
- Swift compilation, XIB decoding and RunnerTests cannot run on this Linux host.
  The host-architecture macOS CI lane now runs the existing Runner test target:
  `xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner
  -configuration Debug -destination 'platform=macOS' -only-testing:RunnerTests
  ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO`. RunnerTests exercises compiled
  menu identifiers, translation, fullscreen labels and preserved commands.
- Existing large Flutter declarations remain documented in
  [the size exceptions](simplification-size-exceptions.md). New production modules
  fit the file, type and function limits.

The implementation reuses native delivery status, the existing selector, ARB
generation and the original Cocoa menu. It separates text admission from
file/voice busy state and interface-language storage from onboarding storage.
No dependencies, Rust contracts, bridge bindings or database schemas changed.
The macOS release build and two native menu tests passed on GitHub. The live
menu identifier test counted 52 items instead of 51 because AppKit inserted an
alternate Full Screen item with the same identifier. All 51 XIB identifiers were
present. The test now checks unique identifiers and a separate test translates
every matching item in the live menu, including AppKit alternates.
The same CI log exposed an unimplemented superclass launch callback. Removing
that call preserves the SIGPIPE suppression; a native regression invokes the
real launch callback and raises SIGPIPE to verify it remains ignored.
CI saves the native result bundle. Verification of these fixes requires the
macOS lane because this development host is Linux.

## PR review verification (2026-10-04)

- CodeAnt close/send finding: confirmed leave freezes new submissions, drains
  accepted native admission, then calls leave. Failed leave reopens admission
  and preserves refused text. No delivery receipt is awaited.
- CodeAnt hidden Retry finding: general action errors and refused text render
  independent existing banners; Retry stays attached to refused text.
- Regression tests failed before the fix for DM, channels and groups. Unit and
  real-router widget tests cover order, repeated close, failed close, blocked
  Retry, reopening input and disposal while draining.
- `flutter analyze --no-pub`: no issues. Full Flutter suite: 1387 passed, 5
  existing native-library tests skipped on Linux.
- Changed executable Dart lines against `0dc50c5`: 28/28 (100%); branches:
  11/12 (91.7%). Formatting: 521 files checked with no changes.
- `git diff --check` and `actionlint .github/workflows/build-macos.yml`: passed.

## Changed files

Application and native code:

```text
lib/main.dart
lib/l10n/app_en.arb
lib/l10n/app_ru.arb
lib/src/features/conversation/clipboard_paste_handler.dart
lib/src/features/conversation/conversation_composer.dart
lib/src/features/conversation/conversation_controller.dart
lib/src/features/conversation/conversation_screen.dart
lib/src/features/conversation/conversation_screen_body.dart
lib/src/features/conversation/conversation_state.dart
lib/src/features/conversation/conversation_text_sends.dart
lib/src/features/lock/mosh_lock_app.dart
lib/src/features/settings/language_settings_card.dart
lib/src/features/settings/profile_settings_section.dart
lib/src/platform/native_menu_labels.dart
lib/src/platform/native_menu_localization.dart
lib/src/state/locale_preference_store.dart
lib/src/state/locale_provider.dart
macos/Runner/Base.lproj/MainMenu.xib
macos/Runner/MainFlutterWindow.swift
macos/Runner/AppDelegate.swift
macos/RunnerTests/RunnerTests.swift
.github/workflows/build-macos.yml
```

Tests and support:

```text
test/features/conversation/conversation_composer_test.dart
test/features/conversation/conversation_close_flow_test.dart
test/features/conversation/conversation_leave_order_test.dart
test/features/conversation/conversation_keyboard_send_test.dart
test/features/conversation/conversation_send_test.dart
test/features/conversation/conversation_text_sends_test.dart
test/features/lock/lock_language_test.dart
test/features/onboarding/first_run_hierarchy_test.dart
test/features/onboarding/first_run_responsive_test.dart
test/features/onboarding/first_run_viewports_test.dart
test/features/onboarding/first_run_wizard_test.dart
test/features/settings/language_settings_test.dart
test/features/shared/conversation_action_error_test.dart
test/platform/native_menu_localization_test.dart
test/state/locale_preference_test.dart
test/support/first_run.dart
test/support/locale.dart
```

Documentation:

```text
docs/Architecture.md
docs/Features/chat-redesign.md
docs/Features/settings-redesign.md
docs/Proposals/issues-45-48.plan.md
docs/Proposals/simplification-size-exceptions.md
```
