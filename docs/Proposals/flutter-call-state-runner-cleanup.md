# Call and conversation-state runner cleanup

Baseline: `9385e9d9e42abc492e1a3b9b4d4814c9c231fc2d`, initially clean.
This round reduces startup for related short Flutter suites: 17 affected runners
become six, and the complete suite goes from 238 runners to 227. All 117 affected
cases remain. No test scenario, assertion, fixture, timeout, retry or production
behavior is removed or changed. The [full identity ledger](flutter-call-state-test-inventory.md)
records every original file + complete runtime describe/test path and its owner.

## Scope and source review

Read root AGENTS, Architecture, voice ADR 0044, testing/analysis configuration and
CI. CI still runs ordinary `flutter test`; it discovers `*_test.dart`, while
sibling case libraries register through exactly one synchronous scoped group.
No CI lists, dependencies, global concurrency or environment changes were needed.
Existing test-policy rules and AGENTS guidance already cover focused cases,
justified skips, historical waits and unique case ownership; no extra guard or
custom test abstraction was introduced.

Root owned every source edit, measurement, document, index operation and commit.
Three read-only reviewers owned disjoint call-UI, call-window/model and state
areas; they inspected implementation/support/history and the immutable resulting
source. Reviews establish source/contract evidence; votes do not establish safety.

| Final owner (under `test/`) | Original scoped modules / cases | Runners | Isolation evidence |
| --- | --- | ---: | --- |
| `features/voice_call/call_prompt_test.dart` | incoming modal 6, outgoing modal 5, confirmation 2, ringing 3 | 4 → 1 | Noop/recording/failing ringtones, widget-local tick/deadline/focus lifecycle; surface override restored. All timing assertions remain on widget clock. |
| `features/voice_call/call_notifications_test.dart` | focus 8, notification lifetime 5, accept retry 2 | 3 → 1 | Every case overrides plugin AND readiness; fake focus handler reset; containers, pending completions and widgets retain original cleanup. |
| `features/voice_call/call_layer_test.dart` | overlay 7, lifecycle 4, stale command 1 | 3 → 1 | Only active/outgoing branches, so no incoming notification initialization; scripted bridge/gateway and local audio captures. Error, teardown, late and replacement guards retained. |
| `features/voice_call/voice_call_orchestrator_test.dart` | orchestrator 9 plus existing capture-config/record-capture/noop capture/playback groups 16 | 2 → 1 | IO leaf cases never start recorder/FFI/player. Real AES-GCM remains; seven callback-local fake clock zones flush and reject pending timers. Original part/support path remains valid. |
| `features/voice_call/voice_protocol_test.dart` | original crypto/codec/jitter/drain 19 plus window-input frames 3 | 2 → 1 | Added frame input uses byte streams, not real pipes/sockets/processes. Retains Unicode boundaries, pre-allocation oversized rejection and truncated-frame errors. |
| `state/conversation_refresh_test.dart` | original refresh 5 plus original session/name/conversation/notification groups 15 and unread derivation 7 | 3 → 1 | Local provider containers and scripted snapshots; notification init/permission use injected fakes. One unchanged repo-asset existsSync check is read-only. Refresh's historical zero-delay stays in its original file. |

Library-private fixtures remain separate. New owners have only namespace imports
and scoped group calls. Existing owners receive those calls before their original
registrations; no original callback or helper changes. The two deleted files,
`voice_io_test.dart` and `conversation_state_test.dart`, contained only imports and
four group registrations each: all eight registrations retain their exact names
in their new owner. They contained **zero test callbacks**. This is the complete
code-deletion justification; there are no DELETE scenario rows.

Independent source checks establish twelve whole-library byte/mode identities,
all original declarations/main statements in the three modified owners, fourteen
unchanged callback definitions there, and preservation of each removed driver's
registrations. Runtime multiset comparison checks file/full name/result/skip
reason/multiplicity, accounting only for documented owner/prefix mapping. Green
remaining tests alone are not the preservation proof.

History reviewed includes `4ee0ec2e` (lifetime/stale commands), `c2a21caf`
(confirmation/occupancy), `ebaaf705` (directional ringing), `c238d04b` (Android
ownership), `889abb46` (provider-owned errors/mute), `78fdf584` (duplicate modal
regression), `1f027781` (previous case ownership), `c03db25b` (orchestrator clock
and late callback), `5541a919` (child-frame boundaries), and existing pruning
`93ef2f30`; state histories `9bc050be`, `37193c3b` and `01a457d6`.
Jitter's increasing-sequence regression remains in its original leaf.
No regression test is deleted.

Size exceptions: the existing long `main` functions in the orchestrator and
refresh owners remain test-declaration blocks; only four/five scoped group
registrations are added. Their callbacks/helpers do not grow. The twelve moved
libraries retain their original size exceptions; no new file exceeds 400 lines
and new registration-only owners stay below 50 lines.

## First pilot, then bounded expansion

Pilot commands: `flutter test --machine` with the four original prompt files,
then only `test/features/voice_call/call_prompt_test.dart`. The reverse original
control used the identical original command. All three ordinary runs passed 16;
a separate candidate `--test-randomize-ordering-seed=42` also passed all 16 and
matched the normalized original identities. The seed run is not included in
same-command timing comparisons.

| Run | Complete wall s | Child CPU s | File interval sum s | Loading sum s | Visible body sum s |
| --- | ---: | ---: | ---: | ---: | ---: |
| pilot-a1 | 8.477 | 19.064 | 23.590 | 19.292 | 4.261 |
| pilot-b1 | 8.193 | 12.369 | 6.159 | 4.315 | 1.827 |
| pilot-a2 | 9.032 | 20.827 | 25.766 | 20.997 | 4.753 |

Only after this module's policy/source/normal/seed verification did expansion
proceed. Expanded scoped commands use the 17 original owners, or the six final
owners listed above, with `flutter test --machine`. Each command keeps ordinary
Flutter defaults. Scoped measurement order was A1, B1, seed42, B2, A2; analysis
and formatting occurred between B2 and A2. All ordinary runs passed all 117,
with exact identity/result/skip/multiplicity equality after registration mapping.

| Run | Complete wall s | Child CPU s | File interval sum s | Loading sum s | Visible body sum s |
| --- | ---: | ---: | ---: | ---: | ---: |
| scope-a1 | 12.773 | 47.264 | 77.604 | 62.158 | 15.348 |
| scope-b1 | 10.349 | 29.155 | 43.573 | 35.400 | 8.106 |
| scope-b2 | 8.863 | 26.035 | 38.854 | 31.618 | 7.170 |
| scope-a2 | 12.821 | 46.810 | 76.037 | 61.527 | 14.448 |

Scoped medians: wall 12.797 → 9.606 s (-24.93%), CPU 47.037 → 27.595 s (-41.33%). Both forward and
reverse controls favor the grouped source in this measured scope; this is not a whole-suite
conclusion.

## Complete-suite comparison

Before any source edit, `flutter test --machine` passed 1,871 plus four native
skips in 138.631 s wall / 1,131.834 child CPU s; file/loading/body sums were
1,057.804 / 440.499 / 615.534 s. This initial diagnostic run is **not** pooled
with the balanced series below.

After scoped checks, the complete command ran consecutively in **A/B/B/A** order,
with A exactly the original test bytes/modes and B exactly the verified candidate.
A guarded snapshot switch refuses unexpected/mixed edits and restores candidate
source afterward. Root ran no other compiler/test/formatter concurrently. Other
agents' independent host work is uncontrolled. Packages, CI, platform gates,
concurrency, Flutter flags and production sources are identical. All command
statuses and full case multisets are checked independently for every run.

| Run | Complete wall s | Child CPU s | File interval sum s | Loading sum s | Visible body sum s |
| --- | ---: | ---: | ---: | ---: | ---: |
| whole-a1 | 143.843 | 1154.064 | 1096.914 | 464.063 | 630.974 |
| whole-b1 | 128.476 | 1049.058 | 979.413 | 409.769 | 568.057 |
| whole-b2 | 128.081 | 1064.583 | 976.760 | 397.187 | 577.952 |
| whole-a2 | 131.596 | 1073.788 | 1002.801 | 421.406 | 579.779 |

Balanced-series medians: wall **137.720 → 128.278 s** (-6.86%), child CPU **1113.926 → 1056.821
s** (-5.13%). File interval sums 1049.858 → 978.087 s. With two samples per state, the median
equals their mean. These observations do not establish a statistical confidence interval or a
universal CI speedup. Both the forward A1→B1 comparison and reverse B2→A2 control favor the
candidate in wall and CPU. The balanced series supports a gain on this host during these runs,
with shared-host/load/cache limits remaining. The unchanged original controls themselves differ by
12.246 s wall, larger than the 9.441 s difference between medians; this is a material limit on
causal attribution from only four runs.

Wall measures the complete command, including Flutter startup. CPU is completed
child/descendant user+system CPU from RUSAGE_CHILDREN. File sums span each worker's
first start through final completion; loading sums use the hidden loading case,
and body sums use visible non-skipped test spans. These intervals overlap across
workers and are neither total elapsed nor exclusive CPU. Startup/first-widget
work can also occur inside a visible test; a lower body sum does not imply its
callback was removed. No CI speed or hardware/native performance forecast.

## Checks and preserved exclusions

- Affected 117 cases: normal runs, seed 42 and reverse original control; exact
  complete-name/result/skip/multiplicity match. Pilot passed before expansion.
- Balanced complete runs all retain 1,871 passes and the same four native skips;
  no original or candidate failure. Baseline-failure worktree reproduction is
  unnecessary because no failure is classified as pre-existing.
- `flutter analyze`: no issues (10.3 s); includes configured unused imports,
  unused elements and dead-code checks. No separate unused-code tool is configured.
- `dart format --output=none --set-exit-if-changed lib test integration_test`:
  816 files, zero changes.
- `python3 -B scripts/test-policy.py` passes; seven existing policy examples pass
  (allowed/forbidden forms, ownership and exceptions). Existing rules unchanged.
- Source AST preservation and byte/mode checks pass; active filename consumers
  checked in lib/test/scripts/CI/docs; chat-redesign's execution pointer updated.
  Historical audits keep their original filenames and measurement chronology.

All four skips are in `test/gateway/real_bridge_dispatch_test.dart`, each with
unchanged reason `native libs not built: mosh-core/target/release/mosh_core.dll / moss-runtime/moss.dll`:

- `undecodable attachment bytes cross as the typed error on every kind`
- `dm: send lands in the DM runtime; a missing id answers typed`
- `channel: send lands in the channel runtime`
- `group: send lands in the group runtime; after leave the lookup misses`

The four skipped real-bridge cases keep their exact native-library missing
reason and original condition. Native initialization/fallback, actual HTTP and
socket/process-global suites keep process boundaries. In particular single-modal
and Android privacy cases stay isolated after tracing unmocked incoming
notification defaults; zero lexical hazards did not prove compatibility.
Existing frame-channel/process-window/coordinator/call-start/cancellation/audio
lifetime cases and real waits stay unchanged. Preferences retain actual atomic
file writes in their existing runner. No invented policy exception or tracker
link was added to move a historical hazard. Real timeout and backoff contracts
are unchanged.

Rust, native/device and integration suites were not run: none of their code,
contracts or binding generation changed. No coverage-percentage/mutation result
is claimed; production and case callback logic are unchanged. Seed 42 is not
proof of all possible test orders. Broader grouping could add global-state
coupling or serialize too much; this change keeps six bounded feature owners.

## Changed files

All paths below are relative to the repository. Twelve exact renames retain
imports/helpers/fixtures in the same directory:

| Original path | Retained case library |
| --- | --- |
| `test/features/voice_call/incoming_call_modal_test.dart` | `test/features/voice_call/incoming_call_modal_cases.dart` |
| `test/features/voice_call/outgoing_call_modal_test.dart` | `test/features/voice_call/outgoing_call_modal_cases.dart` |
| `test/features/voice_call/call_confirmation_test.dart` | `test/features/voice_call/call_confirmation_cases.dart` |
| `test/features/voice_call/call_ringing_test.dart` | `test/features/voice_call/call_ringing_cases.dart` |
| `test/features/voice_call/call_notification_focus_test.dart` | `test/features/voice_call/call_notification_focus_cases.dart` |
| `test/features/voice_call/call_notification_lifetime_test.dart` | `test/features/voice_call/call_notification_lifetime_cases.dart` |
| `test/features/voice_call/call_notification_retry_test.dart` | `test/features/voice_call/call_notification_retry_cases.dart` |
| `test/features/voice_call/call_overlay_test.dart` | `test/features/voice_call/call_overlay_cases.dart` |
| `test/features/voice_call/voice_call_layer_lifecycle_test.dart` | `test/features/voice_call/voice_call_layer_lifecycle_cases.dart` |
| `test/features/voice_call/call_view_command_test.dart` | `test/features/voice_call/call_view_command_cases.dart` |
| `test/features/voice_call/call_window_frames_test.dart` | `test/features/voice_call/call_window_frames_cases.dart` |
| `test/state/unread_providers_test.dart` | `test/state/unread_providers_cases.dart` |

Three added owners: `test/features/voice_call/call_prompt_test.dart`,
`test/features/voice_call/call_notifications_test.dart`,
`test/features/voice_call/call_layer_test.dart`.
Three modified owners: `test/features/voice_call/voice_call_orchestrator_test.dart`,
`test/features/voice_call/voice_protocol_test.dart`,
`test/state/conversation_refresh_test.dart`.
Two removed registration-only drivers: `test/features/voice_call/voice_io_test.dart`,
`test/state/conversation_state_test.dart`.
Documentation: this report, `docs/Proposals/flutter-call-state-test-inventory.md`,
`docs/testing.md`, `docs/Features/chat-redesign.md`.

Private raw JSONL, command/CPU/wall records, guarded source snapshot, original and
candidate hashes/modes, AST checker and read-only reviews reside under
`.git/test-audit/voice-state-next/`; these artifacts are local and not needed by CI.
No production/dependency/CI source changes; no push, deploy or publication.
