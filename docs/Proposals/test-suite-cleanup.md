# Test suite cleanup — 2026-10-30

Historical runtime follow-up: [repeated measurements and process-startup reduction](flutter-test-runtime.md).
The tables below and that follow-up describe intermediate revisions. The
[final original-to-final validation](flutter-final-test-validation.md) records
the completed cleanup, review fixes and all six comparable full-suite captures.

## Scope and checks

Baseline: `3b2b88eb9fc49081be28b98c375c52fd7948adae` (clean `main`).
No production changes, dependency changes or publication. First complete the
thumbnail/media module, then consider target identity tests. Preserve malformed
external input, image budgets, orientation, native dispatch, persistence,
authorization and concurrency coverage. Review deletion evidence independently
of green results. Checks: affected Flutter suites, full Flutter comparison,
`flutter analyze` (also the existing unused-declaration/import check), formatting,
and executable tests for the new CI policy. Native platform suites are inventoried,
not replaced by Dart doubles.

Local tools: Linux, Flutter 3.44.7 / Dart 3.12.2, Node 24.22.1.
CI pins Flutter 3.44.8; local results are not a claim about that SDK or Windows.
Times below include the Flutter launcher, native hooks and runner startup;
sum of file spans is reported separately and can exceed wall time with parallel
execution. Runs use the same machine and cache; they are single samples, not a
benchmark. Raw reports are temporary `/tmp/mosh-test-audit/*` artifacts.

## Decisions: first module

Paths below are complete runner names; top-level tests have no describe prefix.

| File / full group → test path | Protected contract | Decision | Evidence |
| --- | --- | --- | --- |
| `test/features/shared/thumbnail_test.dart` / `createThumbnail` → `returns a base64 JPEG for an image pick` | Image dispatch, JPEG encoding | KEEP | Calls production wrapper; input format differs from output. |
| same / `createThumbnail` → `resizes a large image to the 320px max-edge` | Landscape aspect ratio and cap | KEEP | Separate width-dominant branch. |
| same / `createThumbnail` → `resizes a portrait image by the height edge (longest dim)` | Portrait aspect ratio and cap | KEEP | Separate height-dominant branch. |
| same / `createThumbnail` → `returns null for a non-image pick` | Unsupported MIME fallback | KEEP | Remaining PDF case calls the same wrapper with the same bytes and name as the duplicate below. |
| same / `createThumbnail` → `returns null for a corrupt .png` | Untrusted corrupt input does not escape | KEEP | Runtime validation, not a type guarantee. |
| same / `createThumbnail (video branch) -- media_kit unavailable in flutter test` → `returns null for a video pick when media_kit native backend is unavailable` | Missing native backend is nonfatal | KEEP | Distinct from unsupported MIME and from successful native capture. |
| same / `createThumbnail (video branch) -- media_kit unavailable in flutter test` → `returns null for a real .mp4 fixture when media_kit is unavailable` | Missing backend fallback | DELETE | Both video cases fail at uninitialized `Player` construction before reading media. Keep the garbage-video fallback above; real MP4 success is covered by the app capture test below. This test silently returned when the fixture was absent. Read introduction `0acc5ee1`: fallback, not a separate container-decoding regression. |
| same / `createThumbnail (video branch) -- media_kit unavailable in flutter test` → `returns null for a non-image/non-video pick` | Unsupported MIME fallback | DELETE | Byte-for-byte same PDF call and null assertion as `createThumbnail` → `returns null for a non-image pick`, retained and run. |
| `test/features/shared/media_kit_tracer_test.dart` / `media_kit Player.screenshot() returns JPEG bytes headless` | Library screenshot pipeline | DELETE | Copies app's player/seek/capture flow without calling production. Read introduction `0acc5ee1` and fix `6ad1ef5c`: retain `video attachment generates a miniature and a clear preview`, introduced by that fix, which calls the actual app pipeline and fails if `VideoTrack.auto()` is removed. JPEG decoding in that test subsumes the raw magic-byte assertion. The library-only copy could stay green if the app regressed. Remove its subscriptions, render sleep and imports; keep the shared MP4 fixture. |
| same / `video attachment generates a miniature and a clear preview` | Real app capture and bounded JPEG previews; headless-track regression | KEEP | Checks both outputs, miniature budget and 320×240 dimensions. Native backend gate remains; absent backend is a skip, not proof of success. |
| `test/features/shared/attachment_previews_test.dart` / all five existing test paths | Metadata stripping, original preservation, small images, detailed-image byte budgets and corrupt-image rejection | KEEP | Distinct contracts; exercised as companion suite. |

## Decisions: target identity and test doubles

| File / full group → test path | Protected contract | Decision | Evidence |
| --- | --- | --- | --- |
| `test/gateway/conversation_target_test.dart` / `ConversationRef` → `key round trip` → `every kind renders and parses back` | Three kind round trips | DELETE | Retain and run `dm renders and parses back`, `channel renders and parses back`, `group renders and parses back` in the same group. Those assert the exact wire keys as well as round trips. `ConversationKind` has exactly these three values; the removed loop tests no other error class. Introduction/history `6b390cec`, `12ec671a` concerns grammar consolidation; all malformed keys, colon-bearing IDs and ActiveConversation projection cases remain. |
| same / `DmOfferHost` → `a channel and a group are offer hosts` | Internal typed hierarchy | DELETE | `ChannelTarget` and `GroupTarget` directly extend the sealed `DmOfferHost`; `Gateway.dismissDmOffer` accepts that type. Compiler already checks internal callers. No external-data validation is performed by this test. |
| same / `DmOfferHost` → `a DM is not an offer host` | Internal typed hierarchy | DELETE | Final `DmTarget` directly extends `ConversationTarget`, outside the sealed offer-host hierarchy. This asserts a static type fact; no runtime input or authorization rule is checked. |
| same / all identity, target key, explicit ref key, malformed key and ActiveConversation cases | Conversation isolation, hashing, external key grammar | KEEP | Different IDs/kinds, parsing errors, colon-bearing IDs and adapter projections remain separate. |
| `test/support/scriptable_bridge_test.dart` / `the test bridge sendChannelDmOffer completes (no-op)` | Unscripted double completes | DELETE | Calls only the double's `runScripted` and empty closure without checking recording, failure injection or UI outcome. No production behavior exercised. Shared double failure and state tests remain; real offer tests are untouched. |
| same / `the test bridge sendGroupDmOffer completes (no-op)` | Unscripted double completes | DELETE | Same empty `runScripted` body as channel double, no production contract; deleting a test of a canned no-op loses no app guarantee. |
| same / all other tests | Double state sharing, invitation meshes and typed failures | KEEP | Doubles have real custom logic used by widget tests; mocks alone are not a reason to delete. |
| `test/features/routing/chat_redesign_layout_test.dart` / details lifecycle matrix | Mobile/rail/docked details and kind coverage | MERGE 18→9 | Most expensive file in initial diagnostics (18.910 s span); isolated 20.306 s wall. Final common-code review preserves 320/390/581/1280/1536 boundaries and all kinds at 390/1536. See [UI evidence](flutter-ui-test-cleanup.md), reference R. Other three tests stay. |

## What actually runs

There is no `dart_test.yaml`, custom Flutter test discovery config or extra
unused-code tool. `analysis_options.yaml` includes `flutter_lints`; analyzer
checks unused Dart declarations/imports. No ESLint config exists for scripts.
Rust CI uses Clippy with warnings denied. No linter/dependency was added for
already-covered language checks.

| Lane / command | Selection and exclusions |
| --- | --- |
| CI `flutter-test`: `flutter test` | All 311 `test/**/*_test.dart` files. Native and integration trees are not discovered. Locally 2083 baseline tests: 2079 executed, four skipped; zero failures. |
| Flutter's four observed skips | Every test in `test/gateway/real_bridge_dispatch_test.dart`: undecodable attachment bytes; DM dispatch/missing ID; channel dispatch; group dispatch/after-leave lookup. Gate requires Windows `mosh_core.dll` and `moss.dll`, absent here. This is not a new skip. |
| Thumbnail native capture | Both old capture tests actually ran on this Linux host; retained production capture also ran after cleanup. CI may skip it when libmpv cannot initialize. Missing-backend fallback runs in a separate, deliberately uninitialized isolate. |
| CI Windows `rust-core` | `node scripts/moss-test.mjs --lib` plus every integration target except `multi_device_dm_flow`; separate job runs that target. Ignored workers are launched by parent tests where required. |
| CI macOS `rust-core-macos` | `node scripts/moss-test.mjs` runs default Cargo targets, including the DM flow. |
| Local Cargo inventory | After `node scripts/moss-prepare.mjs`, `cargo test --manifest-path mosh-core/Cargo.toml -- --list` lists 1024 tests across 26 target summaries; `-- --list --ignored` identifies 45 ignored entries. Thus 979 are normally selected as top-level tests in this host/default-feature build. Listing does not execute tests or prove native behavior; feature/platform-specific inventories differ. |
| CI `native-call-media` (Windows/macOS/Linux) | Builds real engine/capture; runs both media crates, then core `native_call::` with `native-media-tests --include-ignored` and independent `device_link_flow native_ --ignored`. These explicit selections activate native tests omitted from ordinary Cargo runs. |
| CI Windows integration / native-device-linking | `integration_test/slice_one_test.dart -d windows`; `native_test/native_peer_io_test.dart`; `node scripts/moss-test.mjs --native-ui` selects `native_test/device_link_test.dart`. Other native/background/Android and voice/video UI tests are not selected by ordinary `flutter test` or these CI steps. |
| Node script tests | CI explicitly selects eight files (source preparation, package/store configuration and compiled PLUS configuration). Locally ran all 11 `scripts/*.test.mjs`: 49 passed, no skip/failure, 6.557 s wall. Three extra files test Android hooks, native camera checks and native source checks. |
| Network diagnostics workflow | Separate workflow runs PowerShell diagnostics, real private-group recovery and repeated native-media diagnostics. Its three-attempt diagnostic loops are not unit-suite retries and are unchanged. |

Ignored native tests include independent-process worker entry points, real audio
hardware, physical IPv4 adapter, public relay/carrier and native-media environment
gates. An ignored worker is not necessarily unexecuted: parents invoke it with
`--ignored --exact`. None was deleted or relabelled as redundant.

## Measurements and verification

Commands for the bounded portions (identical before and after):

```sh
flutter test test/features/shared/thumbnail_test.dart test/features/shared/media_kit_tracer_test.dart test/features/shared/attachment_previews_test.dart --reporter json
flutter test test/gateway/conversation_target_test.dart test/support/scriptable_bridge_test.dart --reporter json
flutter test --reporter json
```

| Selection | Passed before → after | Skipped | Wall seconds before → after | Sum of file spans, seconds before → after |
| --- | --- | --- | --- | --- |
| Media, three files | 15 → 12 | 0 → 0 | 7.415 → 7.197 | 15.401 → 14.184 |
| Targets + bridge double, two files | 45 → 40 | 0 → 0 | 5.963 → 5.933 | 7.575 → 7.910 |
| Initial full diagnostic runs | 2079 → 2071 | 4 → 4 | 150.863 → 146.990 | 1146.925 → 1125.999 |

Initial full runs overlapped some diagnostic/targeted commands and are not an
isolated performance comparison. A sequential isolated full-suite pair is run
below before drawing any timing conclusion. File spans include loading and the
interval from first start to last completion in that suite, not CPU time.
Summed individual visible test-body durations in the initial runs were
614.629 → 607.070 seconds; runner startup/hooks are only in wall time.
No speedup is inferred from test count or tiny bounded-run differences.

Independent read-only review confirmed all eight DELETE decisions against code
and history. Additional evidence: `RealBridgeGateway.dismissDmOffer` exhaustively
switches over the sealed offer-host hierarchy; widening it to include DM would
fail analysis. `conversation_dm_offer_test.dart` retains controller-level
publication and retry/cleanup checks for both hosts. Neither remaining green tests
nor reviewer vote counts substitute for the contract evidence in the table.

Checks already completed: both bounded Flutter suites; full Flutter suite before
and after; `flutter analyze` (no issues); `dart format --output=none
--set-exit-if-changed lib test integration_test` (789 files, no changes);
all Node script tests; `git diff --check`. There were no baseline test failures,
so no failure needed reproduction in a baseline worktree. Rust was enumerated,
not executed; Rust sources, bindings and runtime behavior are unchanged.


## First-pass verified result (before runtime grouping)

Full-path decisions for the expanded Flutter UI scope are in the
[UI evidence and case ledger](flutter-ui-test-cleanup.md). The initial bounded
cleanup removed eight tests; the UI pass removed another 125. Total: **133 fewer
Flutter runner cases**, seven removed test files (311→304). There are no new
Flutter tests. Timer/overlay/tooltip assertions were moved into existing real
interaction tests, and Cartesian matrices were reduced by implementation branch.

Sequential full commands on the same host and caches:

| Metric | Original tests | Final tests |
| --- | ---: | ---: |
| Passed | 2079 | 1946 |
| Skipped (unchanged Windows DLL gates) | 4 | 4 |
| Failed | 0 | 0 |
| Wall time, including launcher/hooks | 145.997 s | 159.049 s |
| Sum of file spans, including loading | 1118.345 s | 1220.885 s |
| Sum of individual visible test-body durations | 607.512 s | 635.701 s |

The original full command was `flutter test --reporter json` with all four
initially edited test files restored byte-for-byte from the baseline commit;
all other test sources were still original at that point. The final command
was identical. The original was restored/cleaned in `try/finally` in the same
workspace, avoiding a different dependency/build cache. No competing test
commands ran during this pair; ordinary source/tool inspection continued.
An intervening cleaned-eight-test run was 144.760 s. The first larger UI run
passed in 156.514 s; the last run above also verifies the corrected noncompact /
stacked large-text viewport. These are individual samples, not distributions.

**No whole-suite speedup was measured.** The complete final run was slower in
these samples, including in aggregate file spans. The three targeted expensive
UI files did get cheaper under the same full-run command:

| File | Cases before→after | File span seconds before→after | Test-body sum seconds before→after |
| --- | --- | --- | --- |
| `onboarding/first_run_viewports_test.dart` | 48→18 | 15.744→10.022 | 13.678→8.078 |
| `routing/chat_redesign_layout_test.dart` | 21→12 | 20.285→16.110 | 17.286→12.696 |
| `conversation/message_selection_row_controls_test.dart` | 27→9 | 14.129→8.667 | 12.341→6.723 |
| Three-file sum | 96→39 | 50.158→34.799 | 43.305→27.497 |

Do not extrapolate these reductions to CI time or attribute the slower unchanged
suites to a cause without another investigation. The measured result is less
work in these three suites, fewer cases/files to maintain, and an enforced
barrier against new untracked test hazards.

Final checks:

- Expanded affected suites: all passed (46.102 s; then exact final full run).
- Final full Flutter: 1946 passed / 4 skipped / 0 failures, as above.
- `flutter analyze`: no issues after removing unused imports/declarations. This
  is also the repository's existing unused-Dart-code check.
- `dart format --output=none --set-exit-if-changed lib test integration_test`:
  782 files, no formatting changes.
- `python3 -B -m unittest discover -s scripts -p test_test_policy.py`: five
  methods with allowed/forbidden forms, issue-local exceptions, immutable counts,
  unrelated callbacks/neighboring tests and Git/CLI history behavior; all pass.
- New guard line coverage via Python stdlib `trace --count` / `--report --missing`:
  92% of 121 executable lines. Branch coverage tooling is not configured here.
- `python3 scripts/test-policy.py` and `git diff --check`: pass.
- All 11 existing Node script test files: 49 passed, no skip/failure (6.557 s).
- `node scripts/moss-prepare.mjs` and both Cargo list/ignored-list commands:
  pass; these enumerate Rust, not execute its runtime suites.

One introduced test failure was fixed, not waived: the merged review timer
assertion initially saw both outgoing and incoming AnimatedSwitcher children.
Settling the completed recording→review transition targets the actual review
consumer. No sleeps, retries or enlarged timeouts were added.

Risks / limits: sparse layout representatives cannot inspect every possible
viewport or artwork pixel. Manual scratch screenshot exporters and their docs
were removed; real behavior suites remain. Windows/macOS/Android/iOS native CI,
real Moss protocol/runtime tests, and Rust Clippy were not rerun locally because
no production/native/binding code changed. Historical real waits/skips remain
frozen debt without invented issue links; the guard's lexical/alias/inline-Rust
limits are documented in [test policy](../testing.md). No baseline failures were
claimed, and no production, dependency, public API or Moss source was changed.

Changed files (both atomic commits):

- `.github/workflows/ci.yml`
- `AGENTS.md`
- `docs/Features/start-menu.md`
- `docs/Features/toasts.md`
- `docs/Proposals/flutter-ui-test-cleanup.md`
- `docs/Proposals/test-suite-cleanup.md`
- `docs/README.md`
- `docs/testing.md`
- `scripts/test-policy.py`
- `scripts/test_test_policy.py`
- `test/features/conversation/attachment_card_preview_test.dart`
- `test/features/conversation/attachment_card_video_overlay_test.dart`
- `test/features/conversation/message_context_menu_test.dart`
- `test/features/conversation/message_copy_test.dart`
- `test/features/conversation/message_focus_test.dart`
- `test/features/conversation/message_selection_mode_test.dart`
- `test/features/conversation/message_selection_row_controls_test.dart`
- `test/features/fingerprint/fingerprint_emoji_test.dart`
- `test/features/fingerprint/fingerprint_lock_test.dart`
- `test/features/onboarding/chat_create_screen_test.dart`
- `test/features/onboarding/first_run_assets_test.dart`
- `test/features/onboarding/first_run_responsive_test.dart`
- `test/features/onboarding/first_run_transition_test.dart`
- `test/features/onboarding/first_run_viewports_test.dart`
- `test/features/onboarding/group_create_screen_test.dart`
- `test/features/onboarding/start_menu_test.dart`
- `test/features/onboarding/start_preview_test.dart`
- `test/features/routing/chat_redesign_layout_test.dart`
- `test/features/settings/settings_screen_test.dart`
- `test/features/shared/confirm_dialog_test.dart`
- `test/features/shared/media_kit_tracer_test.dart`
- `test/features/shared/thumbnail_test.dart`
- `test/features/shared/toasts/toast_motion_preview_test.dart`
- `test/features/shared/voice_composer_permission_test.dart`
- `test/features/shared/voice_composer_timer_test.dart`
- `test/features/voice_call/cpal_ringtone_test.dart`
- `test/features/voice_call/cpal_voice_playback_test.dart`
- `test/features/voice_call/incoming_call_modal_test.dart`
- `test/features/voice_call/outgoing_call_modal_test.dart`
- `test/features/voice_call/voice_capture_test.dart`
- `test/features/voice_call/voice_playback_test.dart`
- `test/gateway/conversation_target_test.dart`
- `test/support/scriptable_bridge_test.dart`
