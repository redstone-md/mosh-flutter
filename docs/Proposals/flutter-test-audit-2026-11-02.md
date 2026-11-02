# Flutter test audit: next reductions

Baseline: `3943074624ba144e732a458ca112b972f9b89887`, clean working tree.
This is an audit, not an implemented optimization. Test bodies, runners,
fixtures, production, dependencies, CI and timing defaults remain unchanged.
Only this report, its identity inventory and the testing-document link change.

## Findings and priority

1. Consolidate identical UI states: **14 fewer registrations**, preserving every
   assertion. Start with one module, not all candidates together.
2. Batch related small suites: **9 runners -> 3 with all 80 cases**, then,
   separately, **4 -> 2 with 12 cases**. No new library is necessary.
3. Five additional registrations are justified DELETE candidates, but cheap;
   treat these as maintenance, not the main performance change.
4. Rewrite two misleading tests to assert their named contracts. This improves
   value; it is not a runtime optimization.

These counts are source-backed proposals, not measured savings. Do not add the
19 registration reductions to the 92 batching cases: some candidates overlap.
The unchanged baseline still has 1890 passes and 246 runners. There is no
after-patch timing in this audit.

## Actual execution and current cost

Read `AGENTS.md`, Architecture, testing policy, ADRs 0013/0015, relevant feature
implementations, local regression history, analyzer configuration and CI.
Three read-only reviewers owned conversation, sessions/routing/onboarding,
and small suites respectively; root owned profiling, settings and this report.
Ownership consolidation and the Connection merge also received independent
source reviews. No reviewer ran a compiler alongside the measured command.

Toolchain: Linux, Flutter 3.44.7 (`84fc5cbb`), Dart 3.12.2; warm existing
workspace/native-hook caches. Other agents use the host; no environment,
concurrency or global timing changes were made.

Command: `flutter test --machine`.

| Baseline measurement | Value |
| --- | ---: |
| Complete command wall, including launcher/hooks | 124.442 s |
| Completed-descendant user + system CPU | 1000.565 s |
| Sum of test-file spans, loading through final event | 944.567 s |
| Sum of loading intervals | 407.826 s |
| Sum of visible, non-skipped case intervals | 535.212 s |
| Passed / skipped / failed | 1890 / 4 / 0 |
| Discovered runner files | 246 |

File/loading/body intervals overlap across parallel workers and are neither
wall nor exclusive CPU. Small gaps explain why loading + body does not exactly
equal file spans. First case intervals also contain per-worker initialization;
deleting the first case can transfer that cost to its successor.

The fresh outcome Counter exactly matches the previous final-code profile:
all file/full-name/result/skip-reason identities and their multiplicities.
The prior same-code observations were 126.792 and 132.814 s wall. The new
124.442 s result is host variation, not an optimization made by this audit.
No baseline failure occurred; no failure-reproduction worktree was needed.

Default discovery runs `test/`, including case libraries through their existing
single scoped owners. CI's `flutter-test` job runs `flutter gen-l10n`, the PLUS
compiled-configuration Node test, and `flutter test`. It does not run
`integration_test/` or `native_test/` by default. CI has separate Windows
slice-one and native device-linking jobs, real Rust/Moss jobs and native-media
jobs. Those are not included in these metrics or proposed for removal.

The four observed skips are all in `test/gateway/real_bridge_dispatch_test.dart`:

- `undecodable attachment bytes cross as the typed error on every kind`
- `dm: send lands in the DM runtime; a missing id answers typed`
- `channel: send lands in the channel runtime`
- `group: send lands in the group runtime; after leave the lookup misses`

All retain `native libs not built: mosh-core/target/release/mosh_core.dll /
moss-runtime/moss.dll`. The media-kit thumbnail probe has another conditional
native-backend gate, but actually passed here. Do not count it as skipped.

Most expensive files by visible case intervals in this run:

| Runner under `test/` | Cases | Body sum s | File span s |
| --- | ---: | ---: | ---: |
| `features/onboarding/conversation_creation_test.dart` | 22 | 13.537 | 15.840 |
| `features/routing/chat_redesign_layout_test.dart` | 9 | 11.492 | 14.386 |
| `features/onboarding/first_run_entry_test.dart` | 26 | 10.645 | 12.609 |
| `features/onboarding/first_run_flow_test.dart` | 26 | 10.120 | 11.699 |
| `features/conversation/message_selection_behavior_test.dart` | 28 | 9.264 | 10.849 |
| `features/conversation/message_selection_mode_test.dart` | 18 | 8.967 | 10.231 |
| `routing/rail_pane_test.dart` | 13 | 8.851 | 14.703 |
| `features/conversation/message_deletion_test.dart` | 20 | 8.232 | 10.060 |

Conversation accounts for 193.483 s of body intervals across 70 runners;
onboarding 54.721 s across eight. This prioritizes source review, not deletion
by duration. The responsive, selection and deletion contracts below remain.

## Assertion-preserving MERGE ledger

Each row identifies one existing full runtime path. Destinations are in the
same file unless specified. MERGE means transfer source-only assertions to the
stated live phase before removing the duplicate registration; it does not mean
the current destination already contains every assertion.

Onboarding declarations live in `*_cases.dart`; their runtime owner is
`test/features/onboarding/conversation_creation_test.dart`. Their full group
prefixes are included below. Both source and runtime owner must be audited.

| Source file / full path | Contract | Decision and retained full path; required evidence |
| --- | --- | --- |
| `test/features/conversation/conversation_attachment_test.dart` / `DM: an offered file shows its name, size and state` | Offered incoming filename, size and ready state. | MERGE into `DM: Download runs against this conversation and locks the button while it does`, before tap: copy all three presentation assertions. Same descriptor/view defaults; held download has not started. |
| `test/features/conversation/conversation_attachment_test.dart` / `channel: an offered file shows its name, size and state` | Same through channel wiring. | MERGE into `channel: Download runs against this conversation and locks the button while it does`, before tap, same three assertions. |
| `test/features/conversation/conversation_attachment_test.dart` / `group: an offered file shows its name, size and state` | Same through group wiring. | MERGE into `group: Download runs against this conversation and locks the button while it does`, before tap, same three assertions. |
| `test/features/conversation/attachment_ownership_test.dart` / `DM: own image/png without transfer state does not download or open` | Own image with no transfer view cannot download/open. | MERGE, with ownership caveat below, into FIRST phase of `DM: each row retains its ownership for the same attachment id`; add immediate exception check before incoming tap. |
| `test/features/conversation/attachment_ownership_test.dart` / `channel: own image/png without transfer state does not download or open` | Same through channel wiring. | MERGE into FIRST phase of `channel: each row retains its ownership for the same attachment id`, same required exception check. |
| `test/features/conversation/attachment_ownership_test.dart` / `group: own image/png without transfer state does not download or open` | Same through group wiring. | MERGE into FIRST phase of `group: each row retains its ownership for the same attachment id`, same required exception check. |
| `test/features/sessions/rail_insets_test.dart` / `desktop: filter chips line up with the search field` | Desktop chip/search x-alignment. | MERGE into `desktop: rows sit as far from the right edge as the left`; identical `pumpRail` at 1200x850, only read-only geometry afterward. Append chip assertion; keep all three existing control-inset assertions. |
| `test/features/sessions/rail_insets_test.dart` / `phone: filter chips line up with the search field` | Phone chip/search x-alignment. | MERGE into `phone: rows sit as far from the right edge as the left`; same proof at 390x844. Keep desktop and phone separate. |
| `test/features/onboarding/group_create_screen_cases.dart` / `group_create_screen tapping Create creates via the bridge and shows the InviteResult card` | URI, footer, removed form, clipboard, Copied state and successful refresh. | MERGE into `group_create_screen Create another group returns to an empty form`. Same fresh bridge and `createNamed('friends')`; retain bridge/clipboard handles and ALL success checks, including `listGroups == 2`, BEFORE reset. |
| `test/features/onboarding/chat_create_screen_cases.dart` / `chat_create_screen a failed create surfaces a persistent inline error (role="alert") and no SnackBar` | Bare-string failure has inline feedback and creates no recent chat. | MERGE into `chat_create_screen the inline error clears on the next successful create attempt`: copy no-SnackBar and empty-list checks BEFORE second tap. Same first error/branch for failAlways/failNext; seeded success is not reached on that attempt. Keep typed failure separately. |
| `test/features/onboarding/channel_join_screen_cases.dart` / `channel_join_screen initial state renders lead, warning, field, button, examples` | Initial public-plaintext warning, lead, input/actions and example chips. | MERGE into `channel_join_screen Join button is disabled when name is empty and enabled after text entry`. Identical initial `pumpJoinStep`; copy ALL initial assertions BEFORE input, particularly the security warning. |
| `test/features/settings/connection_reopen_test.dart` / `restored VPN expansion contains its actual controls` | Restored expansion mounts real lazy controls. | MERGE into `restored VPN disclosure can be collapsed and reopened`; add initial no-adapter visibility BEFORE About. Same Windows 1200x900 empty bridge and navigation prefix; keep restored/collapse/reopen phases. |
| `test/features/conversation/unread_badge_test.dart` / `the count sits on the labelMedium step` | Theme font-size regression. | MERGE into `the count paints with the theme on-accent ink, not white`; identical count=3 mount/Text. Copy exact font-size assertion. |
| `test/features/conversation/unread_badge_test.dart` / `the count renders with tabular figures` | Stable live-number typography. | MERGE into `the count paints with the theme on-accent ink, not white`; copy FontFeature assertion. Keep count=100/`99+` separately. |

History evidence:

- Offered files: introduction `322a4b5a`, opening changes `21e263cf`, paused
  Resume `c238d04b`. Preserve progress, pause, failure, missing-path and actual
  open/error scenarios; literal IDs/body do not select a presentation branch.
- Ownership: read regression `c9f90b3b` across its callback chain. The retained
  first own tap already requires zero downloads/no viewer before incoming tap;
  dropping `own` would violate that assertion. Empty transfer lists remain
  empty even when rows share a descriptor. Preserve the second incoming phase
  and final exception check too. This is source reasoning, not a mutation run.
  Null message IDs also affect selection/semantics/arrival, so the two fixtures
  are not universally interchangeable. Their tested normal, non-selection taps
  use the same unconditional open callback. Keep video/voice, direction
  overrides and dedicated selection/null-ID regressions. Reconsider the merge
  if distinct null-ID ownership evidence appears.
- Rail: `c6a40a7f` introduced the two real layout regressions; both assertions
  and widths remain. No fixture narrowing or route substitution is proposed.
- Group create: `4d98f271` requires explicit refresh, not provider startup alone.
  DM errors: `d16cd642`, `edd593ad`, `efb9a7f5` distinguish error clearing,
  recent-chat isolation and typed wording. Channel warning/validation:
  `2fe2f2da`, `3383a8b1`, `95fb62af`; preserve normalization `49d1a1d0` separately.
- VPN: `0d665c0a` and `ac780e18` fixed PageStorage isolation and restored
  `_visited` mounting. This is app regression coverage, not a Material demo.
  Keep consent-on, adapter-menu, scroll and narrow Back scenarios separately.
- Badge: actual fixes `894ee227`/#12 and `92ca17b0`; every style assertion stays.

## DELETE ledger: low priority

These five removals are eligible because the named successful retained test
already covers the same scenario. All source/destination identities were
checked against the fresh full profile. A future patch must rerun replacements.

| File / full path | Contract | Decision and exact retained test; why loss is acceptable |
| --- | --- | --- |
| `test/features/conversation/conversation_filter_test.dart` / `isMobileBreakpoint 400 wide is mobile` | Interior mobile helper input. | DELETE; retain `isMobileBreakpoint 580 wide is mobile` in the same file. Implementation is exactly width <= 580; same harness/branch, no separate interior regression in `322a4b5a` history. Keep actual 400px screen tests too. |
| `test/features/conversation/conversation_filter_test.dart` / `isMobileBreakpoint 800 wide is not` | Interior desktop helper input. | DELETE; retain `isMobileBreakpoint 581 wide is not` in the same file and actual 600/800px screen/lifecycle cases. Exact 580/581 boundary remains; no distinct 800 helper behavior. |
| `test/features/diagnostics/diagnostics_sections_test.dart` / `DiagnosticsRow renders its label and value` | Row displays Peer/alice. | DELETE; same-file `DiagnosticsGroup renders the uppercased label and its children` mounts the actual same DiagnosticsRow and asserts the exact two strings. Both introduced in `239fc66a`, no separate standalone-context contract/history found. |
| `test/features/diagnostics/mesh_diagnostics_test.dart` / `peerBreakdown 2 direct / 3 relayed` | Direct/relayed detail formatting. | DELETE; same-file `MeshDiagnostics - full mesh renders the group label, the 4 metrics, and the 7 rows` calls the production helper with the same 2/3 fields and asserts the literal output. No extra consumer or branch; both introduced in `0cb53e1f`. |
| `test/features/diagnostics/mesh_diagnostics_test.dart` / `relayBreakdown 1 capable / 4 routes` | Capable/routes detail formatting. | DELETE; same retained full-mesh test invokes the production helper with the same 1/4 values and asserts the literal output. Same history; no separate failure class. |

The two breakdown unit checks cost only milliseconds and remove no worker.
Keeping them is also reasonable if their direct diagnostic value is preferred.
Deleting a first widget test does not remove its worker's warmup. None of these
five is a basis for predicting a noticeable complete-suite improvement.

## Fewer runners without deleting checks

Use the existing sibling `*_cases.dart` and synchronous scoped owner pattern.
The [92-case inventory](flutter-test-audit-2026-11-02-inventory.md) records every
file/full name; KEEP applies to all of them in this independent grouping trial.
Copy case libraries byte-for-byte, preserve relative location and private
fixtures, and add only namespace imports plus `group('stem', module.main)`.

| Bounded group | Source libraries | Cases | Runners before -> proposed |
| --- | --- | ---: | ---: |
| Diagnostics summaries | channel_group_diagnostics, summary_card, diagnostics_sections, diagnostics_summary | 34 | 4 -> 1 |
| Diagnostics network/events | mesh_diagnostics, event_log | 36 | 2 -> 1 |
| Conversation inline widgets | unread_badge, typing_hint, conversation_search_box | 10 | 3 -> 1 |
| Fingerprint, second phase | fingerprint_emoji, fingerprint_lock | 8 | 2 -> 1 |
| Linked-device list, second phase | device_list, device_revocation | 4 | 2 -> 1 |

All thirteen candidate libraries have synchronous registration, no metadata,
setup/teardown-all, policy hazards, actual HTTP/native initialization or
process-global overrides. No executable consumers of their old source paths
were found. Two peer-status test comments name diagnostics_sections and would
need updating. Pure diagnostic-summary tests only read local DTO/localization
values; they need no binding-free process. Existing widget libraries already
use the binding. Library-local fixtures and widget disposal remain essential.

Preserve process isolation for actual HTTP, native initialization/fallback and
process-global probes. Exclude composer recorder construction and history-banner
preference state from this bounded proposal. The earlier 11-runner Dart VM
pilot did not establish a complete-pipeline gain; do not repeat that split or
add a dependency/second mandatory CLI on the basis of its local speed alone.

## Value gaps and remaining waits

| File / full path | Decision | Missing contract and proposed change |
| --- | --- | --- |
| `test/features/conversation/conversation_search_box_test.dart` / `an externally cleared query still reaches the field` | REWRITE | It uses enterText(''), which already clears the controller before parent rebuild. Set the parent's query instead, preserving the element/controller; assert the external prop clears the field. Keep poll/caret regression `1a98f982`. |
| `test/features/diagnostics/event_log_test.dart` / `EventLog - rows 3 events render newest first with time + name` | REWRITE | It asserts presence, not order. Assert relative event order in the existing case; keep the last-40 slice test. Removing reversal appears undetected by current assertions; this is source inference, not an executed mutation result. |
| `test/features/conversation/clipboard_file_paste_test.dart` / `the context menu Paste attaches a copied file, else pastes text` | REWRITE candidate, lower priority | Replace 100 x 10ms maximum polling with file onAttach/text-controller completion observations in the proper real zone; retain both file and text paste traces and real I/O. Actual profile body is 1.520s, not a full second of guaranteed polling. This synchronization rewrite still needs a trial. |

The existing policy scanner found 98 delay sites under `test/`: 60 are
`Duration.zero`, 38 specify positive durations. Counts are lexical sites, not
runtime executions or accumulated seconds; loops and real/fake zones differ.
Search must include generic `Future<void>.delayed`, not only `Future.delayed`.

Two 1050ms real waits in `call_video_renderer_test.dart` protect expiry during
slow decode and stale-image clearing; all four renderer cases total 2.472s of
body intervals. KEEP the contracts from `5541a919`. The implementation uses a
raw Stopwatch and timer; installed fake_async 1.3.3 explicitly cannot control
raw Stopwatch. A blanket fakeAsync replacement would not preserve that test.
A production clock seam is outside the current authorized code scope.

Voice provider/setup waits are mostly 5-30ms; their current body sums are
0.570s/0.228s. Prefer observable completion on a future determinism pass, but
do not trade away setup/accept/end serialization (`6ee3db33`) or late audio
drain protection (`3e1ddd0c`). Existing polling-clock experiments were rejected.
Scanner's two negative-frame waits lack an observable no-result completion;
their remaining 0.6s debt and why it is retained are already documented in the
[scanner audit](flutter-scanner-test-cleanup.md). Do not repeat its finished work.

## KEEP decisions and implementation gates

- Standalone DM-row accessibility and offer-button ancestry in sessions:
  `4cb609e9` deliberately separated their semantics fixture from the two-live-
  Navigator routed test. Matching labels do not prove fixture equivalence.
- markViewed: initial/cached snapshots, reused targets, route-hidden and
  app-hidden states protect separate lifecycle/privacy branches.
- FIFO sends, draft retention, failure retry, leave/drain/refusal, deletion
  scope/permissions and ownership directions protect distinct contracts.
- Real responsive boundaries, reduced motion, mid-animation drag, keyboard
  focus and mouse/touch return-ink regressions remain. Prior RailPane,
  mapped-selection and compound row-control pilots were rejected; no repeat.
- Preserve JSON runtime validation/fallback, handwritten equality, fingerprint
  literal vectors, device revocation and persistence/concurrency cases. A mock,
  a short function or a controlled clock is not evidence for deletion.

First implementation tranche: offered-file consolidation in one module,
24 -> 21 registrations with all three kinds retained. Audit transferred
assertions independently, run original/replacement scopes with alternating
controls and random order, then compare the whole suite before expanding to
the expensive creation runner (22 -> 19) or the grouping proposal.

For each tranche, keep exact source hashes and full outcome Counters, preserve
native skips and all non-candidate identities, run policy/examples, analyze,
format and existing unused-code diagnostics. Distinguish source safety from
green results, scoped savings from whole-command savings, and repeated evidence
from shared-host variation. No global timeout/retry increases or added sleeps.
Existing flutter_lints/analyzer plus the policy guard already cover configured
lint/unused and focus/skip/timeout/retry/wait gaps; no new rule is justified here.

Audit validation: full baseline passed; `flutter analyze` reported no issues
(8.7s), including configured unused-import/element/dead-code diagnostics;
policy passed and all seven policy examples passed. Their invalid-baseline
example intentionally emits a Git fatal message. Formatting validation of
`lib test integration_test` passed: 810 files, zero changes. Every ledger
destination and all 92 grouping identities match fresh successful runtime events. No source
edit means there is no candidate speed, coverage or preservation claim yet.

Raw JSON, stderr, commands, child CPU/wall measurements, baseline/index snapshot,
source reviews and identity checks remain in `.git/test-audit/current-audit/`.
Limits: selective Flutter source audit; no exhaustive Rust/native/PLUS/state
review, physical hardware, Windows/macOS/device run or CI measurement. No
publication, push or deploy.
