# Ordered Flutter test cleanup

Implementation follows the [source audit](flutter-test-audit-2026-11-02.md).
Starting commit: `c5076e3f2d8831735420b65a1e61980943db85e8`, clean.
Linux, Flutter 3.44.7 / Dart 3.12.2; existing warm caches, default concurrency,
shared server. Root owns measurements, tracked edits and commits. Reviewers
prepare private structural tools and inspect immutable source snapshots; no
team compiler runs beside a timed command. No production, dependency, CI,
timeout, retry or native-gate change is permitted by this cleanup.

## 1. Offered-file presentation and Download

File: `test/features/conversation/conversation_attachment_test.dart`.
**24 -> 21 passes**, one runner unchanged. The audit's three MERGE rows identify
all removed full paths and their same-kind Download destinations. All three
original filename/size/ready-state assertions execute before the retained
Download tap for DM/channel/group. Progress, paused Resume, failure, actual
external opening/error and missing-path cases remain unchanged.

History `322a4b5a`, `21e263cf`, `c238d04b` and current AttachmentCard/interpreter
were read. Both initial fixtures are incoming report.pdf/1536/offered with no
path; opaque ID/body differences do not select a rendering branch. The held
Download has not started when presentation is checked. No fixture/helper or
new abstraction is added; one registration template and three repeated screen
mounts disappear.

A separate AST audit checks exactly the three transferred assertions before
first original Download observation/tap, every original target statement and
six unaffected callback templates, imports and helpers. Independent snapshot
review agrees. Exact outcome Counters show only the three ledger registrations
gone; every retained name/result/skip reason/multiplicity matches. A green run
is additional evidence, not the justification for removing those registrations.

Scoped command in both states:

```sh
flutter test --machine test/features/conversation/conversation_attachment_test.dart
```

Three interleaved pairs use A/B, B/A, A/B with byte-guarded original/candidate
restoration. Candidate seed42 also passes all21. No timer/frame is changed.

| Scoped observation, seconds | Before | After |
| --- | ---: | ---: |
| Wall samples | 13.517 / 12.755 / 13.044 | 14.403 / 12.368 / 13.320 |
| Median command wall | 13.044 | 13.320 |
| Median descendant CPU | 19.275 | 19.802 |
| Median sum file spans | 10.832 | 11.109 |
| Median sum loading intervals | 4.612 | 4.602 |
| Median sum visible bodies | 6.199 | 6.484 |

This module does **not** establish a speedup: median wall +2.1%, CPU +2.7%.
Retain the simpler assertion-preserving duplicate cleanup; do not describe it
as a measured runtime improvement. Removing first-case work can move warmup
to the next case, and shared-host observations vary.

Full command before/after: `flutter test --machine`, one observation per state:

| Full observation, seconds | Original | Offered merge |
| --- | ---: | ---: |
| Command wall | 153.038 | 145.463 |
| Descendant CPU | 1242.447 | 1188.225 |
| Sum file spans | 1162.784 | 1110.004 |
| Sum loading intervals | 492.836 | 472.623 |
| Sum visible bodies | 668.242 | 635.795 |
| Passes / skips / runners | 1890 / 4 / 246 | 1887 / 4 / 246 |

The full observation moves in the other direction; this single pair does not
isolate the patch from shared-host load. Neither result proves a repeatable
whole-suite saving. File/body intervals overlap under parallel execution;
they are not elapsed or exclusive CPU. All four native DLL gates are unchanged;
no baseline failure occurred.

Validation: all seven scoped captures and both full captures pass; source and
outcome audits pass, formatting of the touched file is unchanged, test policy
passes, and `flutter analyze` reports no issues. No unused import/helper was
created. Physical/native/platform integration is outside this test-only change.
Raw sources, commands, JSON, stderr, CPU/wall and identity checks are retained
in `.git/test-audit/ordered-cleanup/`.

## 2. Remaining assertion-preserving merges

Seven source files: ownership, unread badge, rail insets, group-create,
chat-create, channel-join and Connection reopening. The audit's remaining
11 MERGE rows apply exactly. Scoped registrations **61 -> 50**, five runners
unchanged; with phase1 the whole expected count is1890 ->1876.

Private AST editors guard original bytes and exact file/full symbolic paths,
build proposed units in memory, remove complete invocation/loop nodes and
transfer assertions at their original phase. Separate audits compare complete
expected units, unaffected callbacks, imports/helpers, dimensions and original
suffixes. Ownership's video specialization keeps its three existing names;
its image no-exception assertion now precedes the incoming tap. Badge keeps
all three style fields and count100. App UI retains plaintext warning before
input, all success/clipboard/refresh checks before reset, non-bridge failure
before retry, both rail widths and initial/restored VPN controls.

Independent reviewers inspect each other's immutable before/after snapshots.
No fixture/clock/route/native seam changes; no new helper or abstraction.
Only already stale group/channel numbered header comments are refreshed.

Scoped command: `flutter test --machine` with these five paths:

- `test/features/conversation/attachment_ownership_test.dart`
- `test/features/conversation/unread_badge_test.dart`
- `test/features/sessions/rail_insets_test.dart`
- `test/features/onboarding/conversation_creation_test.dart`
- `test/features/settings/connection_reopen_test.dart`

Three A/B, B/A, A/B pairs plus candidate seed42 all pass. Exact Counter loss
is precisely11 named registrations; all50 remaining outcomes/multiplicities
match, with no skip or failure. Raw labels are `merge-before/after-1/2/3`.

| Scoped observation, seconds | Before | After |
| --- | ---: | ---: |
| Wall samples | 23.203 / 20.018 / 21.584 | 19.297 / 23.405 / 19.433 |
| Median command wall | 21.584 | 19.433 |
| Median descendant CPU | 56.447 | 50.256 |
| Median sum file spans | 57.047 | 51.527 |
| Median sum loading intervals | 29.001 | 27.741 |
| Median sum visible bodies | 27.996 | 24.721 |

Observed scoped median wall is10.0% lower and CPU11.0% lower; one pair moves
in the other direction. These are local observations under shared-host load,
not a whole-suite/CI speedup or a per-run guarantee. The following grouping
control also validates the complete post-merge source before any renames.

## 3. Bounded runner grouping

After MERGE, all13 selected libraries contain **90 cases**, not the audit's92:
the two badge registrations were already consolidated. Grouping itself removes
no callback, assertion, event, helper or variant. Copies are byte/mode-identical
to the current post-merge sources at `4a46800a`. Three peer-status comments are
updated; five new entry points contain only namespace imports and scoped groups.

| New runner under `test/features/` | Original libraries | Cases | Runners |
| --- | --- | ---: | ---: |
| `diagnostics/diagnostics_summary_contract_test.dart` | channel_group_diagnostics, summary_card, diagnostics_sections, diagnostics_summary | 34 | 4 -> 1 |
| `diagnostics/diagnostics_network_events_test.dart` | mesh_diagnostics, event_log | 36 | 2 -> 1 |
| `conversation/conversation_inline_widgets_test.dart` | unread_badge, typing_hint, conversation_search_box | 8 | 3 -> 1 |
| `fingerprint/fingerprint_contract_test.dart` | fingerprint_emoji, fingerprint_lock | 8 | 2 -> 1 |
| `device_link/device_list_contract_test.dart` | device_list, device_revocation | 4 | 2 -> 1 |

Each original `_test.dart` becomes its sibling `_cases.dart`; names acquire only
the source-stem group prefix within the stated owner. Private libraries/fixtures
remain separate. Current references/consumers, synchronous registration,
metadata/hooks and existing policy hazards were checked before freezing sources.
Actual HTTP/native/global-contract probes remain isolated. Independent source
reviews confirm local DTO/rendering work, controller/focus/dialog disposal and
no binding-absence contract in the included pure helper cases.

Main9->3 and secondary4->2 were measured separately, in that order. Each uses
three A/B, B/A, A/B pairs plus candidate seed42. Commands are `flutter test
--machine` with the original library paths or the stated driver paths; exact
argv is saved in every raw `.time.json`. Full Counter maps are generated from
the fresh post-merge full profile, not reconstructed from the older92-case list.
All78 main and12 secondary identities/results/skips/multiplicities match in
all14 scoped runs. Saved snapshot guards reject third-state edits.

| Scoped median, seconds | Main before | Main after | Secondary before | Secondary after |
| --- | ---: | ---: | ---: | ---: |
| Command wall | 10.761 | 8.652 | 10.094 | 8.795 |
| Descendant CPU | 32.725 | 19.674 | 21.539 | 15.790 |
| Sum file spans | 56.380 | 19.272 | 25.469 | 12.475 |
| Sum loading intervals | 46.244 | 13.983 | 21.392 | 9.299 |
| Sum visible bodies | 9.838 | 5.381 | 4.170 | 3.194 |

Main wall samples:10.247/10.761/11.194 before,8.346/8.652/9.039 after.
Secondary:10.956/9.762/10.094 before,7.977/8.795/8.921 after.
All six local pairs favor the candidate for wall and CPU. Main median wall
is19.6% lower, CPU39.9%; secondary wall12.9%, CPU26.7%. These module savings
do not establish complete-suite acceleration. Controls use the same flags,
workspace and cached inputs, with no other team compiler running.

Source hash/one-owner checks pass for all13 unchanged libraries. `flutter analyze`
reports no issues; format validates815files with zero changes; policy passes.
Native and platform integration remain outside these host widget/unit runs.

Full commands before/after grouping both pass1876 with the same four native
skips. Runner files decrease246 ->238. Exact full Counter normalization changes
only the90 source-stem namespace maps; all other outcomes/multiplicities match.

| Full grouping observation, seconds | Before | After |
| --- | ---: | ---: |
| Command wall | 140.584 | 140.142 |
| Descendant CPU | 1148.585 | 1132.646 |
| Sum file spans | 1075.237 | 1064.319 |
| Sum loading intervals | 455.005 | 451.931 |
| Sum visible bodies | 618.423 | 610.627 |

One full pair does not establish a repeated whole-suite saving. The complete
source comparison after all tranches supplies the later controls. No source
body or test is lost by grouping, independently of these timing observations.

## 4. Five justified DELETE decisions

The original audit records evidence/history for each deletion. Current full
runtime identities below include the new group prefixes; retained callbacks
are token-identical, not replacement smoke tests.

| Runtime file under `test/features/` / full name | Retained contract |
| --- | --- |
| `conversation/conversation_filter_test.dart` / `isMobileBreakpoint 400 wide is mobile` | Same helper branch pinned at580; actual400px screen cases stay. |
| `conversation/conversation_filter_test.dart` / `isMobileBreakpoint 800 wide is not` | Same helper branch pinned at581; actual desktop/search lifecycle cases stay. |
| `diagnostics/diagnostics_summary_contract_test.dart` / `diagnostics_sections DiagnosticsRow renders its label and value` | Retained `diagnostics_sections DiagnosticsGroup renders the uppercased label and its children` mounts the real Row and asserts Peer/alice. |
| `diagnostics/diagnostics_network_events_test.dart` / `mesh_diagnostics peerBreakdown 2 direct / 3 relayed` | Retained `mesh_diagnostics MeshDiagnostics - full mesh renders the group label, the 4 metrics, and the 7 rows` invokes the same production helper/defaults and asserts the literal string. |
| `diagnostics/diagnostics_network_events_test.dart` / `mesh_diagnostics relayBreakdown 1 capable / 4 routes` | Same retained full-mesh case invokes the actual relay helper with1/4 and asserts its literal string. |

AST removes only these complete cases/single-child groups, checks all retained
callbacks/helpers/loop dimensions, and pins implementation/fixture hashes.
History322a4b5a/239fc66a/0cb53e1f and a second source reviewer confirm no separate
interior/standalone regression. The now-unused mesh helper import is removed;
its production functions stay used by the renderer. Stale headers are updated.

Three actual driver scopes pass86 ->81, exactly five Counter identities gone;
all remaining names/results/multiplicities match. This corresponds to34 ->29
cases in the three edited source libraries and32 ->27 AST declarations.
Grouping remains238runners; grouped libraries now contain87cases, not90.

Same-command single observations: wall9.574 ->9.350s, CPU22.480 ->21.369s, file spans21.337 ->20.296s. Commands/JSON are `delete-before/after`. No speed claim is based on these cheap deletions.

## 5. Strengthen existing UI checks and await paste readiness

No case or name is added or removed in this phase:

- `conversation_search_box_cases.dart` / `an externally cleared query still reaches the field` now changes the host's query through its reused setQuery method, preserving the existing controller until the next widget update. It no longer edits that controller directly through enterText(''). The original caret test and all old assertions remain.
- `event_log_cases.dart` / `EventLog - rows 3 events render newest first with time + name` now asserts strict vertical order e3 < e2 < e1, retaining every name/time/detail assertion and the separate last40 case.
- `clipboard_file_paste_test.dart` / `the context menu Paste attaches a copied file, else pastes text` replaces100 x10ms polling with passive onAttach/text-controller observations. Each completion is created before the real menu tap in the same runAsync zone; one original widget pump follows. File IO, both actual menu gestures/pastes and all existing assertions remain, as do all seven unit cases.

The file callback observes completed stream reading/ingest, not the entire
PasteAttachmentAction Future/finally. The following real text paste and its
assertions also require release of the shared in-flight guard. Observer reset
uses finally; the draft listener/controller are cleaned up. The existing long
clipboard widget callback retains its full required composer-constructor
fixture rather than introducing another fixture abstraction solely for length.

Independent source reviews reconstruct both quality files and the clipboard
changes against immutable before/after snapshots. They confirm unchanged old
assertions, test identities, controller lifetime/caret behavior and event
ordering. These are source/trace proofs, not executed mutation-test results.

Both rewritten test libraries pass in their42-case owners. Clipboard before
and after pass the same8 cases with a lower30s CLI pilot cap (no metadata/global
timeout change): wall7.953 ->8.091s, CPU11.521 ->11.832s. No speedup is claimed.
The complete97-case affected scope then passes ordinary and seed42 ordering
with default deadlines, preserving exact identities/results/multiplicities.
Policy now sees97 delay sites versus98 initially;60 zero-delay sites remain.
This removes a polling site, not a measured fixed second from every run.

Final source checks:815 Dart files format with zero changes; flutter analyze
has no issues, including configured unused diagnostics; policy and all seven
allowed/forbidden examples pass. The invalid-baseline example's Git error is
intentional. No new test abstraction, linter rule, dependency, timeout/retry or
skip is introduced. The final whole-source controls below check all changes
against the recorded original rather than attributing host variation to them.
