# Conversation close-flow test cleanup

Baseline: `d4df8ea860da82f17d3e1f1fe70f3039f4526e3e`. Scope:
`test/features/conversation/conversation_close_flow_test.dart`, from twelve
registered cases to nine. All three kinds retain the actual router, their own
localized prompt, cancellation, successful target dispatch and refused-leave
regression. No production, dependency, CI, timing or environment change.

## Evidence and change

Read `ConversationScreen._requestLeave` / `_leave`, `ConversationLeavePrompt`,
`ConversationController.leave`, `conversationCases`, ADRs 0018/0025 and the
introducing commit `322a4b5a`. The prompt-only and cancellation cases have exactly
the same six-statement prefix: new scripted gateway, real routed conversation,
More chat actions, settling, leave menu entry, settling.

Move the prompt-only case's three assertions into the cancellation case at that
same point, before tapping Cancel. They assert the kind's title, confirm button
and zero leave calls before a decision. Preserve every original cancellation
action, frame and postcondition after them. Only duplicate setup/open-dialog
sequences and their separate registrations disappear; no unique assertion is
discarded. Three app mounts are avoided without combining kinds or introducing
another test helper. Imports and shared fixtures remain used and unchanged.

Also read `b743f14a` (PR #52, closes #48/#45), which added the pending-send and
refused-leave regression. All three instances remain token-identical, including
the held send, disabled composer, exact send/send/leave order and successful
submission after refusal. Successful leave tests likewise remain unchanged and
continue to assert each kind's target. Those are distinct contracts, not duplicates
of opening or cancelling a confirmation.

## Case ledger

Every full root-level path below belongs to
`test/features/conversation/conversation_close_flow_test.dart` (no groups).
The declarations expand over `DM`, `channel` and `group`; no kind is dropped.

| Full test path | Protected contract | Decision | Evidence / retained path |
| --- | --- | --- | --- |
| `DM: the leave button asks before it does anything` | DM confirmation title/button and no premature leave. | MERGE | All three assertions run before Cancel in `DM: cancelling leaves nothing behind`; the six-statement prefix is identical. |
| `channel: the leave button asks before it does anything` | Channel confirmation title/button and no premature leave. | MERGE | All three assertions run before Cancel in `channel: cancelling leaves nothing behind`; identical prefix and channel fixture. |
| `group: the leave button asks before it does anything` | Group confirmation title/button and no premature leave. | MERGE | All three assertions run before Cancel in `group: cancelling leaves nothing behind`; identical prefix and group fixture. |
| `DM: cancelling leaves nothing behind` | Prompt before decision; Cancel issues no leave, removes the dialog and keeps the DM screen. | MERGE destination | Original callback statements remain in order, with the three prompt assertions inserted before Cancel. |
| `channel: cancelling leaves nothing behind` | Prompt before decision; Cancel issues no leave, removes the dialog and keeps the channel. | MERGE destination | Same insertion; all original cancellation postconditions and router remain. |
| `group: cancelling leaves nothing behind` | Prompt before decision; Cancel issues no leave, removes the dialog and keeps the group. | MERGE destination | Same insertion; group title and screen checks remain distinct. |
| `DM: confirming leaves the conversation` | Explicit confirmation dispatches to the exact DM target. | KEEP | Callback tokens unchanged; cancellation cannot replace successful dispatch. |
| `channel: confirming leaves the conversation` | Explicit confirmation dispatches to the exact channel target. | KEEP | Callback tokens unchanged; retains kind wiring. |
| `group: confirming leaves the conversation` | Explicit confirmation dispatches to the exact group target. | KEEP | Callback tokens unchanged; retains kind wiring. |
| `DM: confirmed leave drains sends and a failed leave reopens input` | Accepted sends drain before leave; refusal restores usable input. | KEEP | Regression `b743f14a`; complete callback unchanged. |
| `channel: confirmed leave drains sends and a failed leave reopens input` | Same ordering/refusal contract through the channel screen. | KEEP | Complete callback unchanged, including pending operation and recovery. |
| `group: confirmed leave drains sends and a failed leave reopens input` | Same ordering/refusal contract through the group screen. | KEEP | Complete callback unchanged; no concurrency/error assertion removed. |

There are no DELETE decisions that discard behavior. Three registrations are
coalesced only after proving the retained cases reach the same state and contain
every moved assertion. A local AST audit checks the exact duplicate prefix,
merged statement sequence, unchanged independent callbacks, imports, labels and
kind expansion. This source evidence is separate from green test results.

## Measurement protocol

Raw JSON, stderr, wall/child CPU records, immutable source snapshots and local
AST inspection scripts live in `.git/test-audit/close-flow/`. Same workspace,
warm dependency/native-hook caches, serial tests with no concurrent analyzer or
audit compiler launched by this task. Focused comparisons use A/B, B/A, A/B;
only the owned test file is swapped, with byte checks and `finally` restoration.
The first focused control precedes the baseline full run. Full comparisons run
A/B, then B/A; the reverse pair investigates the first full wall-time increase.

```sh
flutter test --machine test/features/conversation/conversation_close_flow_test.dart
flutter test --machine
```

| Focused measurement (seconds) | Before | After |
| --- | ---: | ---: |
| Wall samples | 16.271 / 16.695 / 15.872 | 14.933 / 17.071 / 13.455 |
| Median process wall, launcher/hooks included | 16.271 | 14.933 |
| Median child CPU | 24.419 | 22.831 |
| Median file span, loading included | 13.605 | 12.728 |
| Median loading span | 4.866 | 4.698 |
| Median visible test-body sum | 8.725 | 8.020 |
| Passed / skipped / failed | 12 / 0 / 0 | 9 / 0 / 0 |
| Routed conversation mounts | 12 | 9 |

Local median wall decreases **8.2%**, child CPU **6.5%**. Two pairs favor the
candidate; the second candidate is 2.3% slower than its control. All samples are
retained. This is a small measured reduction with timing variability, not a
claim that every invocation improves.

Full process wall includes launcher/hooks; summed file spans include loading
and overlap under parallel execution. Their sum is neither full process wall
nor CPU. Two full pairs remain a small sample; timing changes in untouched files
cannot all be attributed to this module.

The first full pair is slower overall: wall **160.004 -> 162.438s** (+1.5%),
while child CPU decreases **1273.956 -> 1240.159s**. The changed file itself
decreases **12.256 -> 10.133s** in file span and **9.985 -> 7.726s** in visible
body sum. Several untouched suites take longer in that run; this observation
does not establish the cause of the overall wall variation. A second full
comparison was run in reverse B/A order to check whether the penalty repeats.
Both complete pairs, including unfavorable samples, are retained below.

| Full run, chronological order | Process wall (s) | Child CPU (s) | File-span sum (s) | Loading sum (s) | Visible body sum (s) | Passed / skipped / failed |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| A1: before | 160.004 | 1273.956 | 1219.068 | 521.328 | 695.829 | 1925 / 4 / 0 |
| B1: after | 162.438 | 1240.159 | 1241.857 | 520.410 | 719.504 | 1922 / 4 / 0 |
| B2: after | 149.153 | 1176.734 | 1139.156 | 500.783 | 636.375 | 1922 / 4 / 0 |
| A2: before | 149.902 | 1212.050 | 1143.788 | 496.881 | 645.149 | 1925 / 4 / 0 |

The reverse pair favors the candidate by 0.749s, unlike the first pair.
Across two observations per state, mean full wall is **154.953 -> 155.796s**
(+0.5%), mean child CPU **1243.003 -> 1208.446s** (-2.8%) and mean file-span
sum **1181.428 -> 1190.507s**. All runs discover the same 268 test-process files.
**No full-suite wall-time improvement is demonstrated.** Retain this as a
zero-assertion-loss reduction in repeated setup, with a measured local wall/CPU
gain; neither the full CPU decrease nor a future CI speedup is attributed wholly
to these three mounts. The inconsistent wall direction does not establish a
repeatable full-suite regression either.

Validation:

- All six focused runs and four full runs pass. Outcome Counters differ only
  by the three explicitly merged file/full-name identities, including their
  multiplicity. Every other case/result/skip remains. The four native-DLL skip
  names and reasons match in all full runs. No baseline failure occurred or
  was used to excuse a failure after the change.
- AST inspection independently proves the shared prefix and every retained
  assertion, action and frame. Successful dispatch and concurrency/refused-leave
  callbacks are unchanged. Green remaining tests alone are not the merge evidence.
- `flutter analyze`: no issues, including existing lint/type/unused diagnostics.
  No separate unused-code checker is configured for Dart.
- `dart format --output=none --set-exit-if-changed lib test integration_test`:
  800 files, zero changes. `python3 scripts/test-policy.py` and `git diff --check`
  pass. Existing policy enforcement and exception allowances are unchanged.
- Final test source matches the saved candidate bytes after both comparison
  scripts restore it. No unused imports, fixtures or helpers are created.
  Production, Rust, bindings, dependencies, CI and environment files are unchanged.

## Limits

These are routed widget tests with a scripted gateway. They preserve Flutter
confirmation and command admission coverage, not proof of real native leave,
transport, persistence or physical-device behavior. Those existing suites are
unchanged. There are no new sleeps, skips, timeout/retry overrides, lint rules,
global timing changes or test abstractions.
