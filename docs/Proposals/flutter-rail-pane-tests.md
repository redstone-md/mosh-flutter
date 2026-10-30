# RailPane runtime experiments: rejected

Starting commit: `f45095b8ae684d2b8e4393ce2d42a6e1762aabab`, initially clean.
Outcome: retain the original test code. Three ways of using narrower component
fixtures improved the bounded routing command but did not establish a full-suite
win. Neither a green suite nor a local timing improvement justifies shipping
the observed full-run regressions. No tests, assertions or fixtures are removed.

## Scope and contract audit

The target was `test/routing/rail_pane_test.dart`: thirteen scenarios, twelve
widget tests and one width-calculation test. The shared `pumpRail` fixture mounts
the production route/list/titlebar stack. Six scenarios can use the real pane,
handle, provider/notifier and an in-memory store without the rest of the app;
the other six widget scenarios need actual integration. No dependencies,
production code, clocks, motion durations, retries or timeouts were changed.

History reviewed: [IVO-16](https://linear.app/ivoxygen/issue/IVO-16),
[IVO-29](https://linear.app/ivoxygen/issue/IVO-29), initial commit `5833ad91` and
fix `05475135`. The latter starts a mid-animation drag at the visible edge.
Its real 30ms intermediate frame and assertions stayed intact. The titlebar's
real notifier toggle and its separate 100ms frame check were preserved.
Direct Linear reads found no comments on the two issues; no tracker writes.

All cases below remain at their original full path under
`test/routing/rail_pane_test.dart`; there are no describe groups in the restored
file. Each protects a distinct boundary. Final decision for every row: KEEP.

| Full test path | Protected contract | Decision |
| --- | --- | --- |
| `the list keeps the conversation readable` | Default width and clamp boundaries.  KEEP |
| `dragging the divider resizes the list and saves on release` | Live resize and exactly one save on release.  KEEP |
| `dragging past the narrowest width snaps to the strip and back` | Threshold, actual compact rows and expansion.  KEEP |
| `the titlebar button collapses and restores the chosen width` | Real button wiring, animation and persisted width.  KEEP |
| `reduced motion collapses at once` | System reduced-motion contract.  KEEP |
| `the handle resizes and collapses from the keyboard` | Focus, arrow/Enter handling and width restoration.  KEEP |
| `a collapsed list comes back collapsed after a restart` | Saved layout reflected by the real list and New chat affordance.  KEEP |
| `phones ignore the collapsed desktop list` | Mobile shell breakpoint and navigation.  KEEP |
| `Ctrl+K expands the strip into a focused search` | Actual search focus through the shell shortcut.  KEEP |
| `collapsing keeps the search, its filter and the open chat` | Query/filter and active chat survive collapse.  KEEP |
| `a double click on the handle toggles the list` | Double-click recognition with its controlled 50ms interval.  KEEP |
| `screen readers get the handle as a slider` | Slider values/actions and actual semantic decrement.  KEEP |
| `a drag caught mid-animation starts from the visible edge` | Known visible-edge regression during the real animation.  KEEP |

## Bounded experiments

Same command in every state: `flutter test test/routing --reporter json`.
Every run shown below passed all 15 tests, including two unchanged mobile-back
tests. The first environment-restoration run (26.862s) is retained as a
bootstrap sample, outside the warm comparison. Warm controls are runs 2/3/4.
Earlier observations whose reports disappeared from `/tmp` on environment
resume are excluded. All retained measurements use Flutter 3.44.7 / Dart 3.12.2,
Linux, the same resumed workspace and warm dependency/native-hook caches.

| State | Wall samples (seconds) | Median wall | Median CPU seconds |
| --- | --- | ---: | ---: |
| Original | 13.258 / 14.321 / 13.314 | 13.314 | 23.119 |
| Separate process | 11.667 / 11.203 / 11.747 | 11.667 | 24.608 |
| One grouped runner | 11.620 / 11.975 / 11.642 | 11.642 | 21.844 |
| One file, original order | 11.392 / 11.340 / 11.881 | 11.392 | 20.868 |

- Separate-process candidate: local wall improves but CPU increases
  6.4%; rejected.
- Grouped candidate: two independent case libraries under the existing scoped
  runner pattern, without an extra process. It preserves a lightweight direct
  component entry, but its full-run results below are worse; rejected.
- Minimal candidate: one private `_pumpPane` fixture in the original test file,
  no new case libraries/exports, identical case names and registration order.
  Local wall improves 14.4% and CPU improves 9.7%. Its full-run result also
  fails the requested objective; rejected.

## Full-run measurements

Command: `flutter test --reporter json`, without changed concurrency or filters.
Grouped pairs ran A/B, B/A, A/B. Fresh minimal pairs ran B/A, A/B, B/A, rather
than mixing their final results with the earlier grouped controls. Source
controls restored baseline files byte-for-byte from Git; candidates restored
saved source bytes, with backups, hash checks and restoration in `finally`. No other suite,
analyzer or audit compiler ran concurrently; ordinary report writing continued.
Every full run: **1932 passed, the same 4 native-library skips, zero failures**.
All states start **268 test-process files**.

| Measurement (seconds) | Grouped control | Grouped candidate | Fresh minimal control | Minimal candidate |
| --- | ---: | ---: | ---: | ---: |
| Wall samples | 128.145 / 126.302 / 125.618 | 131.176 / 127.824 / 129.009 | 124.587 / 123.453 / 137.856 | 127.897 / 128.408 / 132.209 |
| Median wall, launcher/hooks included | 126.302 | 129.009 | 124.587 | 128.408 |
| Median completed-child CPU | 1026.207 | 1048.097 | 1016.182 | 1035.520 |
| Median sum of file spans | 963.069 | 985.255 | 950.070 | 978.774 |
| Median sum of loading spans | 408.919 | 418.115 | 399.716 | 423.596 |
| Median sum of visible test-body spans | 552.912 | 565.722 | 549.041 | 557.051 |

Observed full median wall changes: grouped **+2.1%**,
minimal **+3.1%**. These data do not justify
claiming a full-suite speedup. The cause of the wider scheduling/runtime effect
is not established. File/loading/body spans overlap under parallel execution;
they are not total wall time or CPU time, and their medians need not add up.
These local warm samples are not a prediction for CI hardware or cold builds.

## Preservation and final state

- A Dart analyzer AST audit confirmed all thirteen callback bodies match after only
  declared fixture/helper substitutions and the two equivalent notifier-trigger
  substitutions. Every assertion, gesture and explicit clock pump remained;
  original routed fixture, memory store and helpers matched baseline.
- Full name/result/skip Counters, including duplicate-name multiplicity, matched
  the original in every successful full run. The grouped trial used only thirteen
  explicit prefix mappings; minimal trials needed no mapping. Counts alone were
  not the preservation check. The failed initial split compilation probe is
  retained separately and excluded from timing samples; baseline had no failures.
- Candidate and restored-state analysis, formatting and test-policy checks passed.
  Restored formatting covers 800 files with zero changes. The final test
  file is restored byte-for-byte to the starting commit; temporary runners,
  case libraries, fixtures and re-exports were removed. The last successful full
  control checks this exact source state. Existing disk-persistence tests and
  platform gates remain untouched.
- Final tracked change: this report only. No new test abstractions, lint rules,
  production changes, pushes, deployments or tracker writes.
- Native/platform integration and physical input hardware were not run.

Raw JSON, commands, source snapshots, hashes and audit scripts are retained in
`.git/test-audit/rail/`, outside the working tree/index. No optimization should
be inferred from the unchanged green suite: the performance candidates were
explicitly rejected on the whole-run results.
