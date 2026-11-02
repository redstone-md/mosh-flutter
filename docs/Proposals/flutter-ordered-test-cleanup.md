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
