# Screen and route test harness split

Baseline: `1f027781` (clean tree at work start). Scope: test-support modules and
imports only. No test or assertion was removed; production/dependencies/CI flags,
provider ownership, widget trees, clocks, timeouts and retries are unchanged.

## Change and preservation evidence

- `test/support/pump.dart` retains `pumpScreen`, the localized MaterialApp and
  ToastHost. It imports neither GoRouter nor application routes.
- `test/support/pump_route.dart` retains the same `pumpRoute` signature and
  implementation: fresh GoRouter with the production route configuration,
  optional builder, localization and ToastHost.
- `test/support/pump_scope.dart` contains the old `_pump` implementation, renamed
  `pumpScopedApp`. Its body matches the original byte-for-byte apart from the
  function name. Container-overrides precedence and settle/single-frame behavior
  remain identical.
- Dart AST references selected 14 route callers. Their only changes are import
  directives: route-only callers replace the import; mixed callers import both.
  No route re-export/barrel is added to the screen helper.
- Screen/route helper bodies also match the originals after substituting the
  shared function name. All complete file/group/test/outcome Counters match the
  baseline, including duplicate-name multiplicity, in every measured full run.

A static first-party import/export/part walk gives these dependency counts:

| Entry | Before | After | App router after? |
| --- | ---: | ---: | --- |
| `test/support/pump.dart` | 376 | 18 | No |
| `async_switch_tile_test.dart` | 377 | 20 | No |
| `fingerprint_lock_test.dart` | 377 | 27 | No |
| `test/support/pump_route.dart` | — | 377 | Yes, intentionally |

This is a source-dependency metric, not binary size, memory usage or a claim that
runtime drops in the same proportion. Conversation fixtures still import real
screens and routes where their scenarios need them; they were not redesigned.

## Measurements

Linux, Flutter 3.44.7 / Dart 3.12.2; same workspace and warm dependency/native-hook
caches. No other suites ran concurrently during timing. Raw reports and commands:
`/tmp/mosh-test-audit/harness/`. The bounded command was identical before/after:

```sh
flutter test test/app/dropdown_menu_test.dart test/features/shared/async_switch_tile_test.dart test/features/shared/press_scale_test.dart test/features/shared/mosh_dialog_test.dart test/features/shared/chat_error_banner_test.dart test/features/shared/persistence_warning_banner_test.dart test/features/fingerprint/fingerprint_lock_test.dart test/features/device_link/qr_image_test.dart --reporter json
```

Three before/after pairs were measured. For the additional controls after the
split, all affected test-support/import files were temporarily restored from the
baseline and the new state restored in `finally`. Each bounded run passed the
same 25 tests; exact path/name/outcome multisets match.

| Bounded metric | Before | After |
| --- | --- | --- |
| Wall samples (seconds) | 10.466 / 10.378 / 9.703 | 9.467 / 9.682 / 9.296 |
| CPU samples (seconds) | 32.741 / 32.542 / 30.398 | 29.898 / 31.433 / 30.130 |
| Median wall | 10.378 | 9.467 |
| Median CPU | 32.542 | 30.130 |

Bounded wall reduction: 8.8%; median CPU reduction: 7.4%.

The full command was `flutter test --reporter json`. The fresh baseline was
**139.576s / 1132.046 CPU seconds**.
Final full runs: **135.200s / 128.280s / 135.367s**, median **135.200s**.

All four full runs: 1946 passed, the same 4 Windows DLL-gated skips, zero failures.
Total elapsed time and summed parallel file spans are separate:

| Full metric (seconds) | Fresh baseline | After, median of 3 |
| --- | ---: | ---: |
| Wall, including launcher/hooks | 139.576 | 135.200 |
| CPU, all child processes | 1132.046 | 1100.375 |
| Sum of file spans, including loading | 1067.437 | 1031.799 |
| Sum of loading spans | 461.350 | 437.396 |
| Sum of visible test-body durations | 604.679 | 592.855 |

**Do not claim a stable additional whole-suite speedup.** The previous validated
baseline samples at the same head were 134.196 / 137.035 / 139.496s; the new full range
overlaps them. The fresh baseline→after median difference is 3.1%, but one fresh
control cannot separate such a small effect from variation. The confirmed result
is faster focused leaf runs and the removed application dependency from their
harness. Existing 13.6% startup-grouping results are preserved in the
[runtime audit](flutter-test-runtime.md).

## Checks and limits

- Three bounded pairs and three final full runs pass, with exact scenario/outcome
  multiset preservation. All pre-existing test declarations/assertions are intact.
- `flutter analyze`: clean; also checks existing unused-import/declaration rules.
- `dart format --output=none --set-exit-if-changed lib test integration_test`:
  clean. `python3 scripts/test-policy.py` and `git diff --check`: pass.
- The move introduces no new behavior branches. Existing tests exercise both
  scope branches, settle=false, route container/builder and real navigation.
  Test-support files are outside the default lib-only Flutter coverage report;
  implementation equality and existing caller-visible suites provide validation.
- Native/platform integration was not run locally; signatures and implementations
  used by native/integration callers are preserved. Rust/bindings are untouched.
- Do not re-export route support through the lightweight helper. Future callers
  choose screen mounting or actual routing explicitly; documented in
  [test policy](../testing.md).

Changed files:

- `docs/Proposals/flutter-test-harness.md`
- `docs/Proposals/flutter-test-runtime.md`
- `docs/testing.md`
- `test/features/conversation/dm_screen_lock_test.dart`
- `test/features/conversation/dm_state_test.dart`
- `test/features/conversation/group_leave_label_test.dart`
- `test/features/invite_paste/invite_paste_screen_test.dart`
- `test/features/sessions/rail_conversation_keys_test.dart`
- `test/features/sessions/rail_settings_button_return_test.dart`
- `test/features/sessions/sessions_screen_test.dart`
- `test/features/settings/settings_screen_test.dart`
- `test/features/voice_call/android_call_presentation_test.dart`
- `test/features/voice_call/voice_call_navigation_test.dart`
- `test/routing/mobile_rail_back_test.dart`
- `test/support/conversation_cases.dart`
- `test/support/pump.dart`
- `test/support/pump_route.dart`
- `test/support/pump_scope.dart`
- `test/support/rail.dart`
- `test/support/start_menu.dart`
