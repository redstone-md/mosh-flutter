# Flutter test runtime: measured continuation

Follow-up: [screen/route harness dependency split](flutter-test-harness.md) records
the later focused-run optimization separately from these measurements.

Starting head: `93ef2f30c0d6de949a04648c127bdf62f83f4750`.
Original: `3b2b88eb9fc49081be28b98c375c52fd7948adae`.
This completes the runtime objective left unresolved by the
[first cleanup](test-suite-cleanup.md). No additional cases or assertions were
deleted in this continuation; production, dependencies and CI test flags stay
unchanged. No sleeps, timeouts, retries or motion behavior were changed.

## Diagnosis and measured experiment

The previous 146→159s single comparison was insufficient. Repeated controls now
show the original and first-cleanup runtimes overlapping. The first cleanup
removed cheap cases while retaining nearly all per-file process startup.

Old reports showed small unit files spending milliseconds on their tests and
seconds loading the Flutter process. The first bounded experiment used exactly
`flutter test test/util test/invite --reporter json`: six files took 8.410s,
the same 54 tests in two runners took 6.160s. Every original test name/outcome was
matched after stripping the new module prefix. This was checked before expansion.

The final change moves 52 related short unit libraries to sibling `*_cases.dart`
files and registers each synchronous `main` under its own `group` in 16 small
`*_test.dart` runners. Library-private fixtures remain private; setup/teardown
remain scoped to their original group. This removes 36 test-process startups.
It also lets later cases reuse an initialized VM rather than paying that cost
again. The default runner discovers every new runner without a CI command change.

## Full-run measurements

All runs used `flutter test --reporter json`, Linux, Flutter 3.44.7 / Dart 3.12.2,
the same workspace, toolchain and dependency/native-hook caches. Three
original/current pairs alternated in order A/B, B/A, A/B. Test sources were
restored byte-for-byte from Git between those states and restored in `finally`.
The final grouped state then ran three times without source changes. No other
suites ran concurrently; ordinary source inspection continued. This is a warm
local-machine comparison, not a CI forecast or a cold native-build benchmark.

| State | Wall samples (seconds) | Median wall | Median CPU seconds | Passed / skipped / failed | Test-process files |
| --- | --- | ---: | ---: | --- | ---: |
| Original | 157.448 / 157.571 / 159.624 | 157.571 | 1241.277 | 2079 /4 /0 | 311 |
| First cleanup | 158.542 / 152.432 / 164.041 | 158.542 | 1232.904 | 1946 /4 /0 | 304 |
| Grouped unit suites | 137.035 / 139.496 / 134.196 | 137.035 | 1109.930 | 1946 /4 /0 | 268 |

Median wall improves **13.6%** versus the previous head and **13.0%** versus the original. Median CPU use improves **10.0%** versus the previous head.

| Separate measurement (median seconds) | First cleanup | Grouped |
| --- | ---: | ---: |
| Sum of file spans, including loading | 1217.747 | 1046.101 |
| Sum of loading spans | 579.871 | 453.169 |
| Sum of visible test-body durations | 636.420 | 591.469 |

File/loading spans are elapsed intervals, not CPU time; they overlap under
parallel execution and must not be mistaken for total wall time. CPU seconds
come from child-process resource usage. Individual sample data and JSON runner
reports are at `/tmp/mosh-test-audit/paired/`; `summary.json` contains all nine
records. The three final runs all preserve every first-cleanup case identity and
outcome, including multiplicity of repeated names, using a Counter keyed by old
file, full group/test name, result and skip state.

## Source and isolation proof

All 52 case bodies match their pre-grouping sources. 51 files match their old Git
blobs exactly; one `frame_crypto` comment now points to `frame_codec_cases.dart`.
Only entry-point registration is new. Group prefixes are stripped solely for the
identity comparison; no test itself changes how it runs or asserts behavior.
No production/internal runtime declaration, fixture or contract was deleted.

- Native-library initialized/uninitialized probes remain separate.
- The MediaStreamServer singleton/real HTTP suites and mainnet billing client
  tests remain separate. The draft grouping was narrowed after read-only review.
- Deliberate local-HTTP exception: `plus_entitlement_test.dart` combines billing
  and lifecycle unit cases. Neither initializes Flutter binding or HttpOverrides;
  lifecycle uses fake commands, a disposed provider container and disabled polling.
  Billing owns its ephemeral-port server and client and closes both in teardown.
  Keep this runner free of the widget binding's HTTP mock. A second reviewer
  checked this exact boundary rather than treating a green run as proof.
- Android method-channel teardown stays within its original module group.
  Binding-dependent groups contain no incompatible real HTTP tests.

The guard now requires exactly one group-scoped entry point for every
`*_cases.dart` library declaring a synchronous `main`; comments, string lookalikes,
direct unscoped calls, missing owners and duplicate owners are tested. Existing
case-builder helpers without `main` are unaffected. Historical hazard baselines
were not advanced or relaxed; selected moved files contain no wait/skip/timeout
hazards. Full policy: [testing](../testing.md).

## Runner / moved-source map

Each module below moved from `<module>_test.dart` to `<module>_cases.dart` in the
same directory. The runner imports it with a namespace and registers
`group('module', module.main)`; no generic test framework/code generator is added.

| Runner | Module names (all assertions retained) |
| --- | --- |
| `test/util/util_test.dart` | `format`, `format_bytes`, `unread` |
| `test/invite/invite_test.dart` | `invite_detection`, `invite_uri`, `compact_invite` |
| `test/features/voice_call/voice_protocol_test.dart` | `frame_codec`, `frame_crypto`, `jitter_buffer`, `call_drain` |
| `test/features/voice_call/call_commands_test.dart` | `call_control_gate`, `call_dialog`, `call_audio_observer` |
| `test/features/voice_call/voice_io_test.dart` | `call_capture_config`, `record_voice_capture`, `voice_capture`, `voice_playback` |
| `test/features/plus/plus_checkout_contract_test.dart` | `plus_mainnet_catalog`, `plus_mainnet_polling`, `plus_mainnet_fulfillment`, `plus_mainnet_retry` |
| `test/features/plus/plus_entitlement_test.dart` | `plus_lifecycle`, `plus_billing` |
| `test/features/conversation/attachment_models_test.dart` | `attachment_preview_size`, `attachment_miniature_cache`, `clipboard_paste_handler` |
| `test/features/conversation/conversation_models_test.dart` | `peer_label`, `message_selection_model`, `conversation_snapshot`, `conversation_dm_offer` |
| `test/features/shared/image_previews_test.dart` | `attachment_previews`, `preview_color_profile`, `attachment_preview_colors` |
| `test/state/conversation_state_test.dart` | `session_providers`, `chat_names_provider`, `conversation_providers`, `notifications_provider` |
| `test/state/call_dependencies_test.dart` | `voice_call_session_provider`, `android_call_answer`, `production_provider_overrides`, `persistence_warning_provider` |
| `test/state/preferences_test.dart` | `locale_preference`, `rail_layout` |
| `test/platform/platform_contract_test.dart` | `android_background_dek_storage`, `android_waiting_platform`, `mobile_dek`, `app_data_dir`, `mic_permission_config` |
| `test/features/sessions/rail_models_test.dart` | `rail_entry_search`, `revoked_dm_badges` |
| `test/app/app_contract_test.dart` | `mosh_theme`, `distribution_channel` |

A case module remains directly runnable, e.g.
`flutter test test/util/unread_cases.dart --reporter json` (12 passed).
Active feature docs now point to the grouped entry points; historical audit
commands and deletion evidence retain their original filenames.

## Verification and remaining limits

- Full Flutter on the final grouped composition: three green runs, each
  1946 passed, the same four DLL/env-gated skips, zero failures.
- Complete source/name/outcome identity multiset matches the first-cleanup head;
  no reliance on total count alone. The original 133 deletions remain covered by
  the separate [case ledger](flutter-ui-test-cleanup.md).
- `flutter analyze`, including the existing unused-code diagnostics: no issues.
- `dart format --output=none --set-exit-if-changed lib test integration_test`:
  798 files, zero formatting changes.
- Six test-policy test methods pass; repository guard and `git diff --check` pass.
  Guard line coverage is 94% of 143 executable lines via stdlib trace; branch
  coverage tooling is not configured.
- No Rust/native production/binding changes; no native platform suite was rerun.

Future grouping must recheck process-global bindings, HTTP overrides and native
initialization. The registration guard covers the project's direct sibling-import
pattern, not arbitrary dynamically registered suites. Three local samples per
state demonstrate this measured win, but not every CI machine's speedup. Real
network/hardware waits are unchanged. No push, PR, deployment or tracker write.
