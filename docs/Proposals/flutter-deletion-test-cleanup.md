# Deletion status matrix cleanup

Baseline: `f97264e6c891d9dfa125d584655cbd9c19b5f7a1`. File:
`test/features/conversation/message_deletion_test.dart`. Status registrations
decrease from nine to five, total file registrations from 24 to 20. The complete
default suite therefore changes from 1929 to 1925 passing tests, retaining its
four existing native DLL skips. The titlebar fixture change keeps all 12 cases.

## Contract and regression evidence

Read `bfe960c4` (IVO-26): confirmed deletions incorrectly had an extra status
line, and rejected requests fell through to “Request confirmed”. Keep pending,
confirmed and rejected behavior, including the administrator label and absence
of every incorrect/obsolete status string.

`ConversationMessageRow._body` renders deletion markers before its kind-specific
footer/content; `_deletionStatus` switches only on status, not conversation kind.
`ConversationMessage.deletion` reads `metadata?.deletion`. The DM and multi-party
snapshot adapters pass the same metadata object through without interpreting
status. A confirmed-marker screen test remains for every kind, checking this
snapshot-to-row wiring. All three status/error classes remain on the DM screen.

This is evidence about the actual common implementation and its unchanged
adapters, not an assumption that types validate external data. No runtime parser,
native protocol or authorization test is removed.

## Case ledger

Every row is in `test/features/conversation/message_deletion_test.dart` and has
no group prefix; paths below are full test names.

| Full test path | Contract | Decision | Concrete justification / retained replacement |
| --- | --- | --- | --- |
| `DM: a pending moderated deletion shows Awaiting deletion` | Pending request renders its waiting line. | KEEP | Retains the pending branch of the real shared row and the IVO-26 regression assertions. |
| `DM: a confirmed moderated deletion shows no status line` | Confirmed deletion renders only its administrator line. | KEEP | Guards the removed extra-line regression. |
| `DM: a rejected moderated deletion shows Deleted only for you` | Rejection renders local-only status, never confirmation. | KEEP | Guards the wrong-fallback regression independently of pending/confirmed. |
| `channel: a confirmed moderated deletion shows no status line` | Channel metadata reaches the real row. | KEEP | Actual channel snapshot/screen wiring stays; dropping its marker would remove the asserted administrator label. |
| `group: a confirmed moderated deletion shows no status line` | Group metadata reaches the real row. | KEEP | Actual group snapshot/screen wiring stays, including the administrator label. |
| `channel: a pending moderated deletion shows Awaiting deletion` | Shared pending caption through channel wiring. | DELETE | The caption branch is retained verbatim in `DM: a pending moderated deletion shows Awaiting deletion`; the unchanged channel metadata passthrough is exercised by `channel: a confirmed moderated deletion shows no status line`. There is no channel/status combination branch or separate regression. |
| `group: a pending moderated deletion shows Awaiting deletion` | Shared pending caption through group wiring. | DELETE | Same pending branch remains in `DM: a pending moderated deletion shows Awaiting deletion`; `group: a confirmed moderated deletion shows no status line` retains the actual metadata-to-row integration. No separate group/pending behavior exists. |
| `channel: a rejected moderated deletion shows Deleted only for you` | Shared rejection caption through channel wiring. | DELETE | `DM: a rejected moderated deletion shows Deleted only for you` executes the exact rejection regression and all negative assertions. The channel confirmed-marker test retains its unchanged metadata wiring; rendering does not inspect kind here. |
| `group: a rejected moderated deletion shows Deleted only for you` | Shared rejection caption through group wiring. | DELETE | The exact rejection branch/negative assertions remain in `DM: a rejected moderated deletion shows Deleted only for you`; the group confirmed-marker test retains its metadata wiring. The original status matrix was introduced by the common fix `bfe960c4`, not four kind-specific fixes. |

Keep all fifteen permission/action/error cases unchanged: for each of DM,
channel and group, explicit local scope, all-selected eligibility, qualifying
shared deletion, refused deletion retaining selection, and file context-menu
deletion. These include the actual gateway payload and refusal behavior.

## Validation protocol

Two collection-if elements restrict only pending/rejected registrations to DM;
confirmed still registers on every kind. No skip/early-return gates are added.
An AST comparison reconstructs the entire original token stream after removing
only those two registration prefixes and the added enum import. Thus every
remaining fixture, action, assertion, permission and error check stays intact.
Outcome Counters compare exact file/full-name/result/skip identities and
multiplicity; only the four DELETE rows may disappear.

Focused command, three A/B, B/A, A/B pairs:

```sh
flutter test test/features/conversation/message_deletion_test.dart --reporter json
```

Raw JSON, stderr, commands, wall and child CPU records are stored locally in
`.git/test-audit/deletion/`. Controls restore the exact baseline file, candidates
restore saved bytes in `finally`. No other suites/analyzers/audit compilers run
concurrently with benchmarks. Same workspace and warm dependency/native-hook
caches; production, toolchains, dependencies, CI, waits and timing defaults stay
unchanged. These measurements do not forecast CI hardware performance.

| Focused measurement (seconds) | Before | After |
| --- | ---: | ---: |
| Wall samples | 17.706 / 16.529 / 16.724 | 15.167 / 16.492 / 16.162 |
| Median wall, launcher/hooks included | 16.724 | 16.162 |
| Median child CPU | 24.729 | 24.027 |
| Median file span, loading included | 14.480 | 13.958 |
| Median visible test-body sum | 9.907 | 9.140 |
| Passed / skipped / failed | 24 / 0 / 0 | 20 / 0 / 0 |

All three wall pairs favor the candidate, including a near-neutral second pair.
Median wall improves 3.4%, CPU 2.8%; the second CPU pair regresses slightly.
Retain this variation rather than claiming a uniform percentage. The source and
retained-case audits, not these green counts, justify the four DELETE decisions.

An earlier shell-consolidation pilot was rejected and fully restored: three full
controls had median 144.416s wall / 1167.143s CPU; its candidate had 145.506s /
1179.682s despite a faster paired focused cohort. Its local evidence remains in
`.git/test-audit/shell/`; no shell test changes are retained. The three original
full controls are also the unchanged baseline test tree for this final batch.

## Complete-suite comparison

Command in every state: `flutter test --reporter json`. The earlier controls
completed in 143.702 / 144.416 / 144.494s; two earlier final-batch candidates
completed in 149.642 / 156.447s. Both candidates passed 1925 tests with the same
four skips, but that series does **not** establish a full-suite speedup. A third
candidate was interrupted by session suspension and has no completed result;
its partial log is retained and excluded from all statistics.

After resumption, both affected suites passed together (32 tests), analysis,
formatting, policy and both source audits passed again. The first resumed
control attempt was stopped because source restoration overlapped an unfinished
AST audit; that tooling interruption is also excluded. A subsequent successful
pair ran sequentially after every compiler/audit had exited. Both owned source
files were restored from the immutable baseline for the control and from saved
candidate bytes for the final state; `finally` and byte comparisons protected
restoration. Other runtime/test sources stayed unchanged.

| Fresh resumed pair (seconds; one observation per state) | Before | After |
| --- | ---: | ---: |
| Total process wall, launcher/hooks included | 152.158 | 145.597 |
| Completed-child CPU | 1222.796 | 1180.948 |
| Sum of file spans, loading included | 1163.446 | 1113.297 |
| Sum of loading spans | 512.273 | 482.722 |
| Sum of visible test-body spans | 649.284 | 628.734 |
| Passed / skipped / failed | 1929 / 4 / 0 | 1925 / 4 / 0 |
| Discovered test-process files | 268 | 268 |

This pair's wall decreases 4.3% and CPU 3.4%. It is a separate cohort, not pooled
with the older controls or interrupted samples. The unchanged baseline itself
now takes 152.158s rather than its earlier 144.416s median. Given that variation,
the contradictory earlier series and only one fresh pair, a dependable complete-
suite/CI speedup is **not established**. The focused paired measurements above
and in the titlebar audit demonstrate local execution-cost reductions.

File spans start at each suite's loading test and finish at its final test
completion. Their sum overlaps under parallelism and is neither total wall nor
CPU time. Visible body spans exclude hidden loading/setup events. No concurrency,
timeout, retry, motion or environment setting was changed to obtain these data.

Final checks:

- Full outcome Counters before/after differ only by the four DELETE rows; every
  other file/full-name/result/skip identity and multiplicity matches. All twelve
  titlebar cases and all fifteen per-kind deletion permission/action/error cases
  remain. No baseline test failures were observed.
- Candidate source bytes exactly match their verified snapshots after controls.
  Source audits separately establish the unchanged assertions and replacement
  contracts; a green remaining suite alone is not the deletion evidence.
- `flutter analyze`: no issues, including existing lint/type/unused checks.
- `dart format --output=none --set-exit-if-changed lib test integration_test`:
  800 files, no changes. `python3 scripts/test-policy.py` and `git diff --check`
  pass. No guard rules changed or new skips/timing exceptions were introduced.
- Production, Rust, bindings, dependencies, CI and toolchain files are unchanged.
  The four original Windows native DLL gates remain; physical/native integration
  was not rerun for these widget-only changes.

Raw resumed pair data and the comparison summary are in
`.git/test-audit/resume-widget/`; earlier raw data remain in the module folders.

## Risks

Group/channel pending/rejected captions no longer have redundant full-screen
executions. The shared status switch and each kind's metadata mapping remain
covered separately. Add combination tests if future code introduces a kind-
specific status branch. Native Windows DLL tests and physical-device behavior
are outside these widget-only changes.
