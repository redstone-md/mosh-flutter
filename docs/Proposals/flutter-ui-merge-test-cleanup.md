# Shell and compact-rail test consolidation

Starting commit: `07cdf9a0`, clean. `f4e0cea7` subsequently changes only audit
notes. Final source changes are limited to `mosh_shell_test.dart` and
`rail_compact_test.dart`. All nine row-control regressions remain byte-identical
to the start. No production, shared-helper, dependency, CI, clock, timeout,
retry or platform/native gate changes.

## Contract and history evidence

- Shell: three cases use the same connected-DM `shellSession` factory at
  1200x900. Alice/Gina/Frank differ only in id/name. Keep the existing Frank
  close-flow fixture. Assert rail/welcome before opening, then DM/rail and
  absent welcome, then both rail/titlebar semantics **before** any close/menu
  action. Every original close assertion follows on that same mounted screen.
  Read `438ee728`, `4491b09e` and `19c955c4`. Direct-launch regression
  `47593ff3`, mobile, drawer/error and inline navigation remain unchanged.
- Invitation: both cases have exactly `channels: []`, `_collapsed()` and
  `_withOffer()`. Keep the original expansion scenario; move the no-Accept label
  and exact `Expand chat list` hint before its tap. Keep both post-expansion
  assertions. Read `438de7dd`.
- Enable semantics before mounting, as before. Dispose in `finally` immediately
  after the semantic assertions; continue the original close/expand actions on
  the same fixture. A pilot using `addTearDown` failed Flutter's active-handle
  verification, so that introduced cleanup error was fixed explicitly. No
  failure was relabeled as pre-existing, skipped or hidden with timeouts.

Only the declarative desktop close-flow is a narrow exception to the 50-line
function preference, preserving the complete initial/open/semantic/close phases
without a one-use abstraction. No new helper, fake or test DSL is introduced.

## Full-path ledger

All three removed runtime registrations are MERGE decisions, not discarded
assertions. They join the named existing scenarios: shell **9 -> 7**, compact
rail **7 -> 6**; focused total **16 -> 13**. No new test names are added.

| Original file / full runtime test path | Protected contract | Decision and retained path |
| --- | --- | --- |
| `test/features/routing/mosh_shell_test.dart` / `desktop (1200x900): rail + welcome pane render side-by-side; tapping a DM row swaps the chat pane while the rail STAYS` | Desktop rail/welcome before opening; DM/rail/absent welcome and both accessibility nodes before close. | MERGE into `test/features/routing/mosh_shell_test.dart` / `desktop (1200x900): closing a DM routes to /chat so the inline NewSessionPanel reappears while the rail STAYS mounted` |
| `test/features/routing/mosh_shell_test.dart` / `desktop (1200x900): with a DM open, screen readers still reach the rail and the titlebar` | Desktop rail/welcome before opening; DM/rail/absent welcome and both accessibility nodes before close. | MERGE into `test/features/routing/mosh_shell_test.dart` / `desktop (1200x900): closing a DM routes to /chat so the inline NewSessionPanel reappears while the rail STAYS mounted` |
| `test/features/sessions/rail_compact_test.dart` / `screen readers hear an invitation expands the list` | Offer label never announces Accept; exact expansion hint before tap; actual expansion still follows. | MERGE into `test/features/sessions/rail_compact_test.dart` / `an invitation expands the list instead of accepting` |

The original retained close/expansion callback statements remain ordered
subsequences. All assertions from removed callbacks match at the same live UI
stage (the semantic variable is renamed `accessibleOffer`). Three shell
assertions were exact duplicates in the already-open DM state and now execute
once there. Eleven unrelated callbacks and all existing helpers remain
AST-token-identical. Runtime checks verify each retained destination exists and
passes; counters retain exact path/name/result/skip identities and multiplicity.
Safety rests on code/history and stage equivalence, not on green totals or
reviewer votes.

## Rejected pilots

- The identical six-fixture RailPane proposal was already rejected in the
  [earlier full-run audit](flutter-rail-pane-tests.md). Its inadvertent local
  recheck was stopped; the source was restored exactly.
- Twenty-four further mapped selection fixtures passed all 59 cases but made
  their focused command slower. All four helper/test sources were restored;
  see the [selection audit](flutter-message-selection-tests.md).
- Row controls were piloted as 9 -> 3 registrations alongside these UI merges.
  The original primary-focus -> selection -> blocked Enter -> Cancel -> same
  node -> successful Enter sequence was preserved per control after source
  review caught an initially-focused-state gap. Four distinct records retained
  all actual command callbacks and target/ID checks. Three paired focused runs
  observed wall 18.421 -> 15.962s and CPU 48.096 -> 42.108s medians, but complete
  runs below did not establish an aggregate benefit. Keep all nine focused
  regression tests (`c069cb8a`) instead of a more complex combined fixture.
- A repeated-pump alternative failed with a missing cancel control: replacing
  `FutureProvider.overrideWith` callbacks did not reseed the existing element in
  locked Riverpod 3.4.2. No new mutable fixture/API was introduced to work around
  that failed trial. Superseded source variants and failing logs are retained.

## Focused measurements for the retained source only

Identical command in both states:

```sh
flutter test --machine test/features/routing/mosh_shell_test.dart test/features/sessions/rail_compact_test.dart
```

Three warm pairs A/B, B/A, A/B. Byte-check both owned files before switching;
a `finally` restores the final candidate. No other suite, analyzer or audit
compiler runs concurrently. Other agents' unrelated server work remains an
uncontrolled source of contention. File/body/loading spans overlap and are
neither elapsed wall nor child CPU.

| Median, seconds | Original | Final |
| --- | ---: | ---: |
| Full command wall | 14.409 | 13.835 |
| Completed-child CPU | 31.063 | 31.183 |
| Sum of file spans | 22.709 | 22.112 |
| Sum of loading spans | 8.716 | 8.128 |
| Sum of visible case bodies | 13.831 | 13.971 |

- before: wall 14.418 / 14.086 / 14.409; CPU 31.265 / 29.918 / 31.063.
- after: wall 14.265 / 13.835 / 13.233; CPU 31.328 / 31.183 / 27.301.

Observed median wall is 4.0% lower, CPU is 0.4% higher. This does **not** establish
a CPU-cost reduction, a whole-suite speedup or a CI forecast. Retain these two
small changes for removal of demonstrably repeated UI setup and assertions;
do not characterize the rejected broader candidates as shipped optimizations.
The number of runner files remains two here and 255 globally.

## Complete suite and validation

Every row uses `flutter test --machine`, has four identical native skips and
255 process files, and has zero failures. Provisional rows include the rejected
row-control consolidation; they are not measurements of the final source.

| Source state | Passed | Wall s | Child CPU s | File spans s | Loading s | Case bodies s |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Original control1 | 1893 | 152.408 | 1171.978 | 1163.843 | 528.931 | 633.171 |
| Provisional three-file candidate1 (not retained) | 1884 | 164.717 | 1274.618 | 1258.957 | 547.232 | 709.606 |
| Original control2 | 1893 | 160.818 | 1252.845 | 1229.911 | 526.786 | 701.079 |
| Provisional three-file candidate2 (not retained) | 1884 | 152.442 | 1178.715 | 1165.583 | 509.147 | 654.486 |
| Final two-file consolidation | 1890 | 149.479 | 1218.500 | 1145.973 | 492.062 | 652.353 |

The final complete run is 149.479s vs the original152.408/160.818s, but CPU is
1218.500s vs1171.978/1252.845s. These mixed shared-host observations do **not**
establish an aggregate CPU or wall improvement. The retained result is three
proven duplicate registrations removed with every assertion preserved. No
whole-suite acceleration percentage is claimed.

- Final exact runtime Counters: **1893 -> 1890 passed**, the same four skip
  paths/reasons, only the three ledger names removed, no added names and all
  remaining multiplicities/results unchanged. Existing failures: none.
- Both retained suites pass **13** with random-order seed42.
- `flutter analyze`: no issues, including configured unused/dead-code checks.
- `dart format --output=none --set-exit-if-changed lib test integration_test`:
  805 files, zero changes. Existing policy guard and all seven executable policy
  examples pass; the invalid-baseline example deliberately emits its Git error.
- `retained-audit.dart`: removed assertion sequences remain in order; original
  close/expand flows are ordered subsequences; eleven other callbacks/helpers
  remain token-identical. Independent code/history review confirms live-stage
  equivalence and actual source data, rather than relying on green totals.
- Source hashes verify all six rejected test/helper candidates restored exactly,
  including all nine original row-control tests. Production, dependencies, CI,
  AGENTS, scripts and shared helpers have no diff from the starting commit.
- `git diff --check`: passes. No new test abstraction, timing override or gate.

Only tests/docs changed; the default lib-only coverage report does not measure
these test callbacks, and no changed-test coverage percentage is inferred from
it. Real native/device integration and physical accessibility/input hardware
were not run; existing gates and process isolation remain unchanged.

Raw source snapshots, commands, runtime full-path Counters, AST proof and
measurements are under `.git/test-audit/selection-rail-next/`. Nothing was pushed,
deployed or published.
