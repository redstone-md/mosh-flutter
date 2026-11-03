# Pure-Dart runner experiment: not retained

The pilot compiled and passed **109 tests in 11 whole runners**, moving their
suite prefix from `test/` to `dart_test/`. No test was deleted or merged.
The full-pipeline comparison did not establish an aggregate saving. The final
tree restores every original Flutter runner/import and the original dependency,
CI, AGENTS, policy and source-metrics configuration. Only the audit and its
documentation links are retained from the pilot.

The previous single-invite pilot did not establish a complete-pipeline saving:
Flutter remained necessary and another CLI was added. This batch attempted
replacing eleven Flutter worker starts, rather than offloading a few cases from
mixed runners that would still start Flutter. The measurements below evaluate
that hypothesis.

## Migration and protected contracts

Each source below maps to the same path under `dart_test/`; full group/test names
remain unchanged. KEEP/MOVE means retain every callback and assertion.

| Original whole runner | Cases | Protected contract | Decision |
| --- | ---: | --- | --- |
| `test/features/fingerprint/fingerprint_emoji_test.dart` | 6 | Literal security-fingerprint vectors, empty/short/non-hex input and stable case handling. | KEEP/MOVE |
| `test/features/onboarding/first_run_store_test.dart` | 6 | Real atomic file replacement, restoration, overlapping writes, corruption refusal and failed-write recovery. | KEEP/MOVE |
| `test/features/plus/plus_checkout_contract_test.dart` | 11 | Catalog/payment validation, accepted-price/request retention, bounded polling, fulfillment/recovery and disposal failures. | KEEP/MOVE |
| `test/features/voice_call/call_window_frames_test.dart` | 3 | Binary/control-text pipe framing, Unicode byte boundaries, allocation limits and truncated-frame errors. | KEEP/MOVE |
| `test/features/voice_call/native_camera_permission_test.dart` | 3 | Permission refusal, late prompt completion after stop and independent microphone/camera choices. | KEEP/MOVE |
| `test/features/voice_call/voice_call_orchestrator_test.dart` | 9 | Real frame crypto, mute/sequence/direction, reorder, overlapping drains, cancellation, late callbacks and startup failure. | KEEP/MOVE |
| `test/features/voice_call/voice_protocol_test.dart` | 19 | Frame/nonce encoding, real authenticated encryption, invalid-frame refusal, jitter ordering and authenticated playback. | KEEP/MOVE |
| `test/features/vpn/bypass_adapter_test.dart` | 13 | NIC eligibility, APIPA exclusion, stable candidate ordering, default selection and adapter labels. | KEEP/MOVE |
| `test/invite/invite_test.dart` | 21 | Runtime external-input validation, family-specific errors and canonical compact invitation routing. | KEEP/MOVE |
| `test/support/scriptable_bridge_test.dart` | 13 | Faithful seeded/shared conversation state, invitation/organization behavior, consent and typed bridge failures. | KEEP/MOVE |
| `test/support/scriptable_gateway_test.dart` | 5 | Fake send/poll/leave state and recorded arguments consumed by caller tests. | KEEP/MOVE |

The counts and exact original full names were prepared from the stored
`onboarding-bounded/full-original-2.jsonl` profile and then verified against the
fresh complete baseline before running the pilot.

## Source compatibility evidence

The locked `flutter_rust_bridge` 2.12.0 package has no Flutter SDK dependency.
Its generated support selects an IO or JS implementation; the inspected IO
support and the project's generated Rust DTO libraries do not import
`dart:ui` or `package:flutter/`. Generated DTOs therefore are not, by themselves,
evidence that a test requires a Flutter engine.

The selected test/case/helper closure has no `testWidgets`, `WidgetTester`,
Flutter binding initialization, platform-channel setup or `RustLib.init()`.
The camera runner uses injected permission futures and `ScriptableBridge`;
it never requests an actual OS permission or starts native capture.
Its production timer is cancelled synchronously by each session's `stop()`.
The orchestrator keeps its existing controlled clock and pending-timer checks.
No timer interval, delay, timeout, retry or gate is changed.

Cryptography remains real: frame tests call the same AES-GCM seal/open functions,
including tamper/wrong-key checks and the jitter regression for strictly
increasing sequences. The file-store tests still use real temporary directories
and atomic replacements, rather than an in-memory persistence substitute.
PLUS checkout uses its existing fake commands/billing and controlled clock.
Its real HTTP authorization/capability probe remains outside this batch.

This source analysis is additional evidence beside the runtime comparison below.
The pilot changed framework imports from `flutter_test` to `package:test`;
the already resolved `test` version was 1.31.0.

## Shared fixtures remain canonical

The candidate moves 23 files: 11 drivers, 11 case libraries and the orchestrator
part. It changes 22 framework URI tokens and 14 relative helper URI tokens.
All non-URI source bytes are identical in the fixed before/after snapshots.
Case libraries remain siblings of their original owning driver; the private
orchestrator part remains beside its driver.

These fifteen helper/part files stay at their existing paths. They have no
`flutter_test` imports and need no edits or copied counterparts:

- `test/support/call_video_frames.dart`
- `test/support/gateway_snapshots.dart`
- `test/support/message_builders.dart`
- `test/support/plus/mainnet_fakes.dart`
- `test/support/scriptable_bridge.dart`
- `test/support/scriptable_bridge_calls.dart`
- `test/support/scriptable_bridge_conversations.dart`
- `test/support/scriptable_bridge_diagnostics.dart`
- `test/support/scriptable_bridge_invitations.dart`
- `test/support/scriptable_bridge_native_calls.dart`
- `test/support/scriptable_bridge_network.dart`
- `test/support/scriptable_bridge_organizations.dart`
- `test/support/scriptable_gateway.dart`
- `test/support/scripted_calls.dart`
- `test/support/scripted_conversations.dart`

Hash checks confirm these canonical helpers are unchanged. Reverse
import/export/part inspection found no consumer outside the 23-file batch that
imports a moved source. Shared Dart statics remain suite-isolate local; this
does not make actual native process-global initialization safe to combine.

## Explicit exclusions

| Runner | Reason to retain the existing separate Flutter process |
| --- | --- |
| `test/gateway/real_bridge_dispatch_test.dart` | Real `RustLib.init()` and four existing native-library gates; native owners are process-global. |
| `test/features/plus/plus_mainnet_billing_test.dart` | Actual loopback HTTP requests protect bearer-token privacy, durable request IDs and recovery routes. |
| `test/features/voice_call/voice_call_cancellation_test.dart` | Two valuable crypto/lifecycle cases still use three zero-delay waits; moving them needs an independent determinism/policy review. |

The locked VM test runner uses suite isolates in kernel/source mode.
An isolate is not a separate OS process for native library state. This is why
the real native and HTTP probes are not folded into the ordinary Dart batch.

## Registration, references and verification

Accepting the candidate requires an explicit direct dev dependency, Dart CI/test
command, documented complete local command and policy coverage for `dart_test/`.
Keep exactly one group-scoped owner for every moved case library. Count the
additional CLI and build-hook cost in the whole pipeline.

There are no runner-specific references in `scripts/` or `.github/`. Their
generic test command still needs the new Dart lane. Earlier benchmark,
cleanup and validation reports keep paths/commands valid at their own commits;
do not rewrite historical timing commands. Current instructions should point to
this source map and the new complete command.

Private snapshots, all 46 source hashes, the 109-name outcome inventory,
suite-path normalization and reversible byte-checked applicator are under
`.git/test-audit/conversation-next/dart-candidate/`. Only the suite path is mapped
back for comparison; full test names and result/skip multiplicities must match.

## Scoped runtime comparison

Starting layout: `d53915ed`, after the independently verified conversation
cleanup. Actual pre-move command (the eleven original paths from the table):

```sh
flutter test --machine \
  test/features/fingerprint/fingerprint_emoji_test.dart \
  test/features/onboarding/first_run_store_test.dart \
  test/features/plus/plus_checkout_contract_test.dart \
  test/features/voice_call/call_window_frames_test.dart \
  test/features/voice_call/native_camera_permission_test.dart \
  test/features/voice_call/voice_call_orchestrator_test.dart \
  test/features/voice_call/voice_protocol_test.dart \
  test/features/vpn/bypass_adapter_test.dart \
  test/invite/invite_test.dart \
  test/support/scriptable_bridge_test.dart \
  test/support/scriptable_gateway_test.dart
dart test --reporter json dart_test
```

The second command replaces the first in the candidate. Three interleaved pairs
run A/B, B/A, A/B, with exact original source restoration for each control. Every
run passes the same 109 full suite/name/result/skip identities; none is skipped.
Only the suite prefix is normalized. The inventory also matches the fresh full
baseline at `4998d309`, not just the older preparation profile.

| Observation, seconds | Flutter control | Dart candidate |
| --- | ---: | ---: |
| Full-command wall samples | 9.490 / 10.860 / 10.086 | 3.091 / 2.007 / 2.245 |
| Completed-child CPU samples | 20.944 / 23.567 / 23.500 | 7.026 / 5.261 / 6.032 |
| Median command wall | 10.086 | 2.245 |
| Median completed-child CPU | 23.500 | 6.032 |
| Median sum of file spans | 58.498 | 9.034 |
| Median sum of loading spans | 57.613 | 8.136 |
| Median sum of visible case bodies | 0.797 | 0.715 |

Scoped median wall is **77.7% lower**, CPU **74.3% lower**. Source, native crypto,
file I/O and assertions are unchanged; most of the observed work was loading.
The wall clock includes CLI launch/build hooks. Child CPU uses completed
descendants' user + system time, excluding unrelated agents' CPU. File spans
overlap and are not elapsed time or CPU. Shared-host contention still affects
observations; this batch result does not establish a complete-pipeline speedup.

## Temporary runner integration (reverted)

- Declared the already resolved `test: ^1.31.0` as a direct dev dependency.
  `flutter pub get --offline` changes only its lockfile dependency classification;
  no package version or SHA changes.
- CI required both `dart test dart_test` and `flutter test`; AGENTS.md and
  `docs/testing.md` documented both. Widget/native entry points kept Flutter.
- Extended the existing lexical test-policy scope to all Dart VM helpers/cases,
  retaining frozen exceptions and the one-owner check. An executable temporary
  Git fixture verifies untracked case detection, focus rejection, unreasoned
  skip rejection, local issue/reason acceptance and duplicate-owner rejection.
- Included `dart_test/` in source metrics so case libraries and the orchestrator
  part remained classified as tests.

All of this temporary integration was reverted with the source move. Both CLI
costs must be included; a fast batch alone is not aggregate runtime evidence.

## Complete-pipeline result and decision

Control command: `flutter test --machine`. Candidate command sequence:
`dart test --reporter json dart_test`, then `flutter test --machine`, measured
as one process tree including both launchers/build hooks. No flags changed
concurrency, timeouts, retries or hardware. Complete runs were interleaved A/B/A/B
on a host shared with other agents; samples were not selected by direction.

| Complete run | Wall s | Child CPU s | Sum file spans s | Sum loading s | Sum case bodies s |
| --- | ---: | ---: | ---: | ---: | ---: |
| Original `4998d309`, before UI cleanup | 147.939 | 1202.088 | 1127.459 | 484.667 | 641.032 |
| UI cleanup, Flutter control 1 | 120.614 | 965.777 | 919.734 | 408.735 | 509.587 |
| Dart candidate 1 | 136.292 | 1105.325 | 1035.470 | 441.059 | 592.780 |
| UI cleanup, Flutter control 2 | 144.894 | 1174.033 | 1112.760 | 486.073 | 624.943 |
| Dart candidate 2 | 144.159 | 1168.885 | 1097.138 | 444.302 | 650.972 |

The original has 1921 passes/four native skips/256 entry points. Every other row
has the same 1893 passes and four skips. Control has 255 Flutter entry points;
candidate has 244 Flutter + 11 Dart suites. Exact Counters match all names,
outcomes, skip reasons and multiplicities after only the explicit 109-path map.
The UI difference from the original is exactly 35 removed registrations and
seven retained replacement registrations, documented in the
[conversation audit](flutter-conversation-contract-test-cleanup.md).

Controls alone vary by 24.281s wall and 208.257s child CPU. The later adjacent
pair differs by only -0.735s wall / -5.148s CPU; the earlier pair moves in the
opposite direction. Aggregate benefit is **not established**. These observations
also do not isolate the pilot as the cause of a regression. The isolated 77.7%
wall improvement cannot justify adding a mandatory CLI/dependency for the stated
goal of reducing complete-suite cost. Revert the pilot, preserve all 109 existing
tests in Flutter, and retain the independently verified UI cleanup.

Final source restoration is byte-checked against all 23 original files and 15
canonical helpers. Offline dependency resolution restores the original lockfile
without version changes. The eight temporary policy examples passed during the
pilot; the extra Dart-tree example was reverted with its unused policy scope.
Final retained-tree checks are recorded in the conversation audit. No production
behavior, native integration, public contract or dependency is changed.

Raw profiles, exact commands, counters and measurements remain under
`.git/test-audit/conversation-next/`, including `whole-comparison.json` and the
rejected metadata patch. No publication, push or deploy was performed.
