# Conversation layout test consolidation

Scope: `test/features/routing/chat_redesign_layout_test.dart`. Baseline:
`dfc45243676862a6626283c0813eccd895fc4734`. Production code, toolchains,
dependencies, CI concurrency and timing defaults remain unchanged.

## Contract review

The file has no describe/group prefix; the names below are full test paths.
All rows refer to `test/features/routing/chat_redesign_layout_test.dart`.

| Full test path | Protected contract | Decision | Evidence |
| --- | --- | --- | --- |
| `details choice survives resizing and resets for another chat` | Explicit close survives resize; another DM starts with default details state. | REWRITE fixture | Keep every interaction/assertion from regression commit `0f23d747`. Its existing `seedSessions` already replaces the rich DM history with empty Alice/Bob snapshots. Construct the gateway directly instead of first populating unrelated groups, channels, files and voice messages. |
| `conversation types have distinct cues in rail, filter and header` | Kind-specific rail glyphs/colors, header kind and filter chips. | MERGE | Keep its original assertions and real routes. While each kind is already open at 1536px, also run the complete docked-details lifecycle and its optional desktop export. |
| `Alice at 1536px: responsive details and usable chat` | DM details initially docked, no modal; close removes panel and header button reopens it. | MERGE | Retain all assertions/actions and `desktop-dm` export inside the Alice iteration of `conversation types have distinct cues in rail, filter and header`, at the same width with the same rich fixture. Only a redundant fresh app mount/open is removed. |
| `Design team at 1536px: responsive details and usable chat` | Group details initially docked, no modal; close and reopen. | MERGE | Same lifecycle/export retained in the Design team iteration of `conversation types have distinct cues in rail, filter and header`; same real group route, width and fixture. |
| `#general at 1536px: responsive details and usable chat` | Channel details initially docked, no modal; close and reopen. | MERGE | Same lifecycle/export retained in the #general iteration of `conversation types have distinct cues in rail, filter and header`; same real channel route, width and fixture. |
| `Alice at 320px: responsive details and usable chat` | Minimum-width populated chat; modal open and Escape close. | KEEP | Minimum supported phone width, including file/voice layout. |
| `Alice at 390px: responsive details and usable chat` | Populated mobile DM, modal lifecycle and export. | KEEP | Real DM header wiring and mobile layout. |
| `Design team at 390px: responsive details and usable chat` | Populated mobile group, modal lifecycle and export. | KEEP | Real group header wiring and mobile layout. |
| `#general at 390px: responsive details and usable chat` | Populated mobile channel, modal lifecycle and export. | KEEP | Real channel header wiring and mobile layout. |
| `Alice at 581px: responsive details and usable chat` | Two-pane shell immediately above the 580px breakpoint, with modal details. | KEEP | Separate shell/layout branch. |
| `Alice at 1280px: responsive details and usable chat` | Details dock at the exact desktop threshold; close and reopen. | REWRITE | Keep the same rich fixture, width and assertions; share the lifecycle helper with the three 1536px iterations. |
| `Ctrl+K focuses the list from an active chat and returns to mobile list` | Shortcut transfers composer focus to list search; mobile returns to the sessions route. | REWRITE fixture | Keep both widths, real router, composer focus and keyboard sequence. One empty Alice DM suffices; message history and unrelated chats are never inspected by these assertions. |

`DmScreen`, `GroupScreen` and `ChannelScreen` each supply their real header to
`ConversationScreen`. Its `_detailsDocked` threshold and `_chrome` open/close
callbacks are common. The retained cue test already navigated all three routes;
the added lifecycle checks run immediately after checking each header kind.
Every desktop lifecycle finishes open, and cross-DM state reset remains a
separate regression test. The merged tests are no longer individually
selectable by their old names; failures still identify the exact kind through
the retained route/header checks and lifecycle assertions.

There are no DELETE decisions or removed assertions. Preserve all five widths,
rich message/file/voice fixtures at layout boundaries, and all six optional
screenshot names. Calls to `pumpShellApp` drop from 13 to 10; registered tests
from 12 to 9. The optional exports remain manual inspection aids, not golden
checks.

## Measurements and verification

Commands, raw JSON, stderr, wall and child CPU records are stored locally in
`.git/test-audit/redesign/`; these artifacts are outside the tracked tree.
Both states used this workspace, Linux, Flutter 3.44.7 / Dart 3.12.2 and warm
dependency/native-hook caches. Three unchanged baseline runs preceded three
candidate runs. No other suites, analyzer or audit compiler ran concurrently
with timing commands; source reads and report writing continued. These are
local measurements, not a CI forecast.

```sh
flutter test test/features/routing/chat_redesign_layout_test.dart --reporter json
flutter test --reporter json
```

| Focused measurement (seconds) | Before | After |
| --- | ---: | ---: |
| Total wall samples, launcher/hooks included | 20.891 / 22.383 / 21.782 | 19.225 / 19.574 / 18.830 |
| Median total wall | 21.782 | 19.225 |
| Median child CPU | 31.695 | 28.411 |
| Median file span, loading included | 19.427 | 16.987 |
| Median visible test-body sum | 14.618 | 11.846 |
| Passed / skipped / failed | 12 / 0 / 0 | 9 / 0 / 0 |

Focused median wall decreases **11.7%**, child CPU **10.4%**. Sequential cohorts
cannot rule out machine drift; every candidate sample is faster than every
control sample. Frame durations and settling calls were not shortened.

| Full-run measurement (seconds; one sample per state) | Before | After |
| --- | ---: | ---: |
| Total wall, launcher/hooks included | 153.165 | 143.934 |
| Child CPU | 1211.904 | 1161.294 |
| Sum of file spans, loading included | 1165.443 | 1097.823 |
| Sum of loading spans | 504.237 | 477.458 |
| Sum of visible test-body spans | 659.538 | 618.715 |
| Passed / skipped / failed | 1932 / 4 / 0 | 1929 / 4 / 0 |
| Discovered test-process files | 268 | 268 |

The full candidate completed 9.231s sooner in this pair. One sample per state
does not establish a repeatable full-suite speedup, and improvements across
untouched files cannot be attributed to this change. No existing failures were
observed. All four skips still require the original Windows native DLLs.

File spans run from the loading test's start through the last test completion in
each suite. Their sum overlaps under parallel execution and is neither total
wall time nor CPU time. Visible test-body spans exclude hidden loading/setup
events; independently calculated medians need not add up.

Separate preservation checks compare parsed Dart token sequences against the
immutable baseline: rich fixture/open/export helpers and setup are unchanged;
original cue assertions, the reset regression, mobile details and keyboard
actions/assertions remain. The shared desktop helper matches the old lifecycle
exactly except for optional export dispatch and added kind-specific failure
reasons. Outcome Counters compare file, full test name, result, skip state and
multiplicity; only the three documented registrations may disappear. A green
count alone is not the evidence for consolidation.

Validation:

- Three focused runs and one full run per state; no failures.
- Full outcome Counter comparison passes with exactly the three documented
  merges; all other identities/results/skips match, including multiplicity.
- `flutter analyze`: no issues (also the existing unused Dart code check).
- `dart format --output=none --set-exit-if-changed lib test integration_test`:
  800 files, zero changes.
- `python3 scripts/test-policy.py` and `git diff --check`: pass. No new timing
  overrides, skips, sleeps or guard rules were introduced.
- The same focused suite also passes with `MOSH_REDESIGN_SCREENSHOTS` set.
  It writes exactly the six existing `desktop-{dm,group,channel}.png` and
  `mobile-{dm,group,channel}.png` exports, at 1536x900 and 390x900 respectively.
  This opt-in export run is excluded from timing comparisons above.

Risks: the three desktop lifecycles now share one mounted application and test
result. Each still uses its own real route and retains kind-specific assertion
reasons. Optional exports reflect this shared browsing session rather than
independent fresh sessions; they have never been golden assertions. Rust, real
native transport/audio and physical devices were not changed or rerun.
