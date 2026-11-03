# Details layout phase audit: candidate rejected

Baseline: `759a0f33003f61e74677c38507e85ca057273a86` (`test(vpn): group network contract runners`).
Scope: `test/features/routing/chat_redesign_layout_test.dart` and its unchanged `shell_harness.dart`.
Outcome: restore both tracked source files byte-for-byte, including modes.
No test, assertion, route, fixture, helper, timing setting or dependency changes
are retained. This audit and its testing-policy pointer are the only changes.

The candidate preserved all nine tests and the measured UI checkpoints, but did
not establish a wall-time improvement: **16.746 → 16.817 s
(+0.43%)**, with only one of three clean pairs faster. Child CPU
median is **25.788 → 24.897 s (-3.45%)**, favoring
the candidate in two pairs. Reject it for the requested elapsed-time objective.
Do not revive this five-site replacement from its green tests/frame counts alone.

## Baseline and scope

Read AGENTS, Architecture, relevant ADRs 0013/0015, analyzer/CI/test policy,
the real router/shell/conversation/details/drawer and current test support.
Flutter CI still runs `flutter test`; native and device integrations are separate.
No existing configured linter or policy gap calls for a new rule or dependency.
The previous redesign, UI-matrix and rejected RailPane/component-fixture audits
were checked before proposing this new operation-level trial. Prior route/mount
and rich-fixture reductions are not repeated.

Command, identical expanded argv for every ordinary measurement:

```sh
flutter test --machine test/features/routing/chat_redesign_layout_test.dart
```

Initial baseline: nine passes, no skips/failures, one runner. The full default
discovery at this starting commit is 1858 passes, four native skips and 216
runners, verified by the preceding VPN-round full captures. That is historical
full-suite evidence, not a new full run in this round. Current scope remains nine.
Existing failures: none. No baseline-failure worktree was required.

| Capture | Complete wall s | Child CPU s | File span s | Loading s | Visible body sum s |
| --- | ---: | ---: | ---: | ---: | ---: |
| module-a1 | 16.478 | 24.145 | 14.299 | 3.833 | 10.431 |

## Nine retained contracts

All paths below are full runtime names in
`test/features/routing/chat_redesign_layout_test.dart` (no group prefix).
Every final decision is KEEP: only a temporary wait-rewrite was trialed.

| Full test path | Protected contract | Final decision / trial scope |
| --- | --- | --- |
| `details choice survives resizing and resets for another chat` | Explicit close1536, resize1280 preserves hidden details; another same-kind DM starts with default details. Regression `0f23d747`. | KEEP original; trial only changed the wait after close. Retain Alice→Bob, actual route and resize. |
| `conversation types have distinct cues in rail, filter and header` | Three actual route/header kinds, glyphs/colors/chips and close/reopen docked details for each kind. | KEEP original; trial changed two waits inside the shared details helper. |
| `Alice at 320px: responsive details and usable chat` | Minimum-width populated DM/file/voice layout and actual modal open/Escape close. | KEEP original; trial changed the two modal waits. |
| `Alice at 390px: responsive details and usable chat` | Mobile populated DM wiring, modal lifecycle and optional visual export. | KEEP original; same two modal waits trialed. |
| `Design team at 390px: responsive details and usable chat` | Mobile populated group route/header, modal lifecycle and optional export. | KEEP original; same two modal waits trialed. |
| `#general at 390px: responsive details and usable chat` | Mobile populated channel route/header, modal lifecycle and optional export. | KEEP original; same two modal waits trialed. |
| `Alice at 581px: responsive details and usable chat` | Immediately above mobile shell breakpoint, details still modal. | KEEP original; same two modal waits trialed. |
| `Alice at 1280px: responsive details and usable chat` | Exact docked-details threshold, close/reopen lifecycle. | KEEP original; shared details helper waits trialed. |
| `Ctrl+K focuses the list from an active chat and returns to mobile list` | Real composer focus, modifier/key sequence, search focus and mobile return at two widths. | KEEP; callback and every helper it calls unchanged even in the candidate. |

The same-kind reset regression is not replaced by the cross-kind cue tour:
those routes recreate different screen types. Keep all five widths, original
rich message/file/voice data, genuine gestures/routes and six optional export
names. No deletion/replacement of a test, business rule or regression is proposed.

## Diagnostic phase profile

Fresh original-source run instrumented exact AST await sites with a Stopwatch,
the binding's controlled clock and `pumpAndSettle`'s returned frame count.
Ten mounts and thirteen row-open operations execute across the nine workflows.
The initial mount alone took 1.610046 s in this diagnostic; later mounts ranged
0.133311–0.296518 s. First-worker initialization is not an eliminated budget.

| Original await site | Calls | Frames | Controlled clock ms | Diagnostic wall s |
| --- | ---: | ---: | ---: | ---: |
| `shell_harness.dart:63:pumpWidget` | 10 | 10 | 0 | 3.464211 |
| `shell_harness.dart:73:pumpAndSettle` | 10 | 40 | 4000 | 0.912872 |
| `chat_redesign_layout_test.dart:108:pumpAndSettle` | 13 | 90 | 9000 | 3.528037 |
| `chat_redesign_layout_test.dart:159:pumpAndSettle` | 1 | 2 | 200 | 0.113359 |
| `chat_redesign_layout_test.dart:162:pumpAndSettle` | 1 | 3 | 300 | 0.151280 |
| `chat_redesign_layout_test.dart:121:pumpAndSettle` | 4 | 8 | 800 | 0.439696 |
| `chat_redesign_layout_test.dart:124:pumpAndSettle` | 4 | 8 | 800 | 0.513066 |
| `chat_redesign_layout_test.dart:251:pumpAndSettle` | 5 | 40 | 4000 | 0.794050 |
| `chat_redesign_layout_test.dart:255:pumpAndSettle` | 5 | 10 | 1000 | 0.308491 |
| `chat_redesign_layout_test.dart:276:pumpAndSettle` | 2 | 8 | 800 | 0.199853 |

This table contains leaf awaits only. Outer `pumpShellApp`, `_open` and
`_checkDockedDetails` include nested awaits; never add them to these leaf costs.
The selected panel sites execute nineteen times and consume 68 pump frames,
6800 controlled-clock ms and 2.168662 diagnostic wall seconds. A single pump at
each site means nineteen local pump calls, not proof of 49 fewer total suite
frames or 6.8 real seconds saved. Decorative work may move to later settling or
teardown. Controlled time and Stopwatch wall are separate quantities; profiling
overhead makes this run unsuitable for the ordinary performance medians.

## Exact candidate and independent preservation checks

An AST edit guarded by the exact baseline changes only five original invocation
sites, `tester.pumpAndSettle()` → `tester.pump()`:

- `_checkDockedDetails`, original lines121/124: close and reopen (eight calls).
- The reset regression, line159: close before the unchanged resize (one call).
- Responsive modal workflow, lines251/255: open and Escape close (ten calls).

No route transition, initial mount, resize or keyboard-shortcut settling changes.
The panel's visibility callbacks are synchronous; the drawer also requests focus
post-frame. Desktop close changes Row↔chat and may remount descendants, so a
single frame requires evidence beyond merely finding the expected widget.

An independent AST audit checks the entire expected candidate unit: original
imports/declarations, action/assertion sequences, loops, rich fixtures, routes,
resize, key events and export helpers are otherwise identical. A read-only
reviewer separately reconstructed the exact five replacements from Git bytes
and checked the implementation/history. No new helper abstraction is added.

Additional diagnostic baseline/candidate runs each pass all nine original tests.
At all nineteen immediately post-action checkpoints their complete captures
match: URI, panel/docked/drawer counts, focus-widget type and drawer ancestry,
every onstage Text value and its global rectangle to six decimal places.
The capture itself adds no pump or clock advance before taking that snapshot.

Limits: this is not a comparison of every pixel/render box/semantic node,
focus-node identity, native lifetime completion or scheduler idleness. The
diagnostic async wrapper/logging can affect delivery before the next action;
therefore the uninstrumented workflow measurements remain necessary. Optional
screenshots are at unchanged pre-toggle or route-settled points, not exhaustive
paint evidence for these changed post-toggle phases.

## Ordinary performance measurements

All nine outcomes, full names, results, skip flags/reasons and multiplicities
match exactly in every ordinary and diagnostic run. Profile/capture timings
are not pooled with ordinary runs. Sources restore exact baseline/candidate
bytes and modes between observations; third-state edits and HEAD drift fail.

The first exploratory pair is retained separately below. A local Python
test-policy command briefly overlapped `module-a2`'s launcher. Before inspecting
its results, the correction was recorded: exclude that entire first pair from
acceptance medians and add a clean reverse pair. No own compiler, analyzer,
formatter or second Flutter suite overlaps any timed run. Other agents share
the server; no environment, concurrency or cache policy is changed.

| Capture | Complete wall s | Child CPU s | File span s | Loading s | Visible body sum s |
| --- | ---: | ---: | ---: | ---: | ---: |
| module-a2 | 17.791 | 26.574 | 15.672 | 4.350 | 11.285 |
| module-b1 | 17.875 | 26.442 | 15.845 | 4.185 | 11.617 |

Primary clean order: B/A, A/B, B/A. These are all three clean pairs, not a selection
of favorable results from the exploratory pair. All exploratory/initial results
remain recorded with their reason and classification.

| Capture | Complete wall s | Child CPU s | File span s | Loading s | Visible body sum s |
| --- | ---: | ---: | ---: | ---: | ---: |
| module-b2 | 16.817 | 24.892 | 14.656 | 4.068 | 10.554 |
| module-a3 | 16.746 | 25.788 | 14.540 | 4.375 | 10.128 |
| module-a4 | 15.850 | 23.565 | 13.607 | 3.991 | 9.582 |
| module-b3 | 16.933 | 24.897 | 14.715 | 3.891 | 10.781 |
| module-b4 | 16.746 | 25.049 | 14.599 | 4.233 | 10.330 |
| module-a5 | 18.260 | 27.431 | 15.729 | 5.442 | 10.255 |

| Clean median, seconds | Original | Candidate |
| --- | ---: | ---: |
| Complete command wall | 16.746 | 16.817 |
| Completed-descendant user+system CPU | 25.788 | 24.897 |
| Test-file span | 14.540 | 14.656 |
| Loading | 4.375 | 4.068 |
| Visible test-body sum | 10.128 | 10.554 |

Wall includes the entire command/launcher/hooks/cleanup; CPU is completed
descendant `RUSAGE_CHILDREN`. File/loading/body intervals are separate quantities,
not exclusive CPU. A scoped command has one file; global file intervals would
overlap under parallel execution. Independently calculated medians need not add.
No full-suite, CI, cold-build or hardware speedup is inferred from these values.

## Restoration, verification and limits

The performance gate failed, so restore both test and harness to baseline Git
bytes/modes. The candidate is rejected on scoped timings; the full-suite,
random-seed and manual-export acceptance checks are not run. The
earlier full counters do not stand in for a new candidate full run. No native,
device/live-network, Moss/Rust, custom-font or optional-export mode is exercised
in this round. No new flaky failure is hidden or called pre-existing.

After restoration, `flutter analyze`, full Dart formatting validation,
`python3 scripts/test-policy.py`, its seven existing examples and diff checks
verify the final unchanged source. No separate unused-code checker is configured;
the analyzer includes unused imports/elements/dead-code diagnostics. No orphan
imports/fixtures or test abstractions remain. No coverage/mutation result is
claimed; no production line or contract changes.

Existing AGENTS/testing policy already requires contract evidence, scoped owners
and controlled timing; no duplicate AGENTS text, new rule, exception, focus,
skip/todo, timeout/retry or real sleep is introduced. Future timing changes must
preserve actual layout/focus phases and demonstrate savings in ordinary runs.
Fewer explicit local pump calls alone do not justify a runtime optimization.

Private original/candidate/capture sources, commands/raw JSON, timings, exact
Counters, phase records and independent review are retained under
`.git/test-audit/layout-phases-next/`. Nothing is pushed, deployed or published.
