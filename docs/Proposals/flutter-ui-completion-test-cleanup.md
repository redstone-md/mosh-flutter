# UI completion and repeated setup cleanup

Baseline: `f88807a5a00bc278641d4857e4a78141d5cdfb5f`. Scope: four existing
entry-point files under `test/features/`: `sessions/sessions_screen_test.dart`,
`shared/media_viewer_test.dart`, `shared/attachment_picker_test.dart` and
`shared/chat_drop_zone_test.dart`. The focused package changes from 32 to 31
cases; no entry-point file or unique assertion is removed. Production,
dependencies, CI configuration and environment files are unchanged.

## Decisions and evidence

Read the tests with sessions rail/action code, MediaViewer's file/network branch,
AttachmentPicker, ChatDropZone and shared ingest. Read `40231a09` (Issue 08,
shared RailItem), `130653b7` (local image URI regression), `d0ea73b6` (PR #58,
issue #56), the architecture and ADR 0041. Work proceeds sessions first, then
viewer, then the shared ingest callers, checking each before expansion.

The following names are full root-level paths except the explicitly named
`ChatDropZone /` group. File names identify the four paths listed above.

| File + full test path | Protected contract | Decision | Evidence / retained case |
| --- | --- | --- | --- |
| `sessions_screen_test.dart` / `the offer row renders through the shared rail row, dismiss X included` | The invite and its dismiss action use the shared RailItem, with the peer title. | MERGE | Same `_channelOfferBridge()` and routed mount as `pending channel DM offer renders one rail row and dismiss removes it`. Move the complete row lookup/title assertion immediately after that mount, before interaction. |
| `sessions_screen_test.dart` / `pending channel DM offer renders one rail row and dismiss removes it` | Offer rendering, dismiss dispatch, accept, session refresh and DM navigation. | MERGE destination | Retain all original actions/assertions, adding the structural regression before them. Ten independent tests, including accessibility, accept/dismiss errors and refresh, remain unchanged. |
| `media_viewer_test.dart` / `a file:// image loads from disk, not the network` | Local image URLs with a Unicode filename, spaces and comma load through disk. | REWRITE synchronization | Same real PNG, URI, HTTP denial, mounting and cleanup. Await the widget's actual provider inside the existing real zone, then pump. Keep old assertions and additionally require decoded RawImage pixels. Ten other cases remain unchanged. |
| `attachment_picker_test.dart` / `the paperclip forwards both previews and unchanged original bytes` | Picker preserves original bytes, bounded inline miniature and clear JPEG width 320. | REWRITE synchronization | Same 640 x 480 PNG, platform fake, callback actions, byte/dimension assertions and platform restoration; await actual onPick/onError completion. |
| `attachment_picker_test.dart` / `the paperclip reports a bad preview and never sends the image` | Corrupt images report previewUnavailable and cannot reach onPick. | REWRITE synchronization | Same corrupt bytes, fail guard, typed error and exception assertions. Both callback paths signal completion; unexpected success still fails. |
| `chat_drop_zone_test.dart` / `ChatDropZone / ingests a dropped file through onAttach (end-to-end)` | MethodChannel drop delivers unchanged real file bytes, name, MIME and both previews. | REWRITE synchronization | Preserve entered/performOperation events, actual file read, error assertion, metadata, bytes, preview budget/decode and widget pumps. Wait for actual attach/error callback. |
| `chat_drop_zone_test.dart` / `ChatDropZone / an unreadable dropped image reports its preview failure` | An unreadable image reports previewUnavailable without attaching. | REWRITE synchronization | Same real corrupt file, platform events, failure guard and error/exception assertions. Five other ingest/overlay/disabled cases remain unchanged. |

There is no DELETE decision discarding behavior. Only the duplicate sessions
fixture/router prefix and one registration disappear; the retained case executes
the entire structural check in the same state. Imports and fixtures remain used.
No new test abstraction is introduced.

The viewer loses one unconditional 100ms pause. Four ingest loops previously
polled every 5ms up to 400 iterations. They usually exited early: their combined
nominal 8s ceiling is not eight seconds of saved normal-run time. Each now awaits
a test-owned Completer, created inside `runAsync` before tap/drop. Callback data
is recorded before completing; unexpected-result guards complete before throwing
so their failure cannot leave the test waiting for the expected branch.

A prototype created the Completers in the fake zone. All four changed cases
timed out even though callbacks had supplied data; that failed verification and
its sources remain in `ingest-check-fake-zone.*` / `rejected-fake-zone-*`. It is
not a baseline failure or a successful timing sample. Moving creation into the
existing real-zone callback fixes delivery without changing inputs or budgets.

## Budgets and guard

The old polling ceiling was nominally 400 x 5ms. Four local Future.timeout calls
retain a **2s completion bound**, with local reasons and the actual historical
[issue #56](https://github.com/redstone-md/mosh-flutter/issues/56). These are not
raised deadlines or retries. The wall deadline is now explicit; the old polling
loop could overrun its nominal ceiling through scheduling delay. A missing
callback fails within this bound instead of falling back to Flutter's default
ten-minute widget-test deadline. Real file IO and image processing stay intact.

Existing Flutter lints do not enforce reason/issue metadata. Extend the existing
Python guard's timeout matcher to include `.timeout(...)`, covering Future and
Stream methods. The original matcher missed this form; a local probe reproduces
that false negative on the baseline version. No new plugin or dependency.

Guard examples cover ordinary/whitespace/onTimeout forms, ignored comments,
strings and lookalike names, local valid/invalid exceptions, frozen budget values
and multiplicity. All thirteen pre-existing Dart method timeouts retain their
original values and frozen per-file allowance at `3b2b88eb`; the historical
baseline is not advanced. Focus/skip/retry/sleep policies and native gates remain.

## Measurement and validation

Raw JSON, stderr, process wall/child CPU records, source snapshots and structural
inspection tools live locally in `.git/test-audit/ui-tail/`. Focused A/B, B/A,
A/B comparisons restore only the four owned Dart files with byte checks and
`finally`. Same workspace and warm caches; no other suite, analyzer or audit
compiler is launched by this task during timed runs. The first focused control
precedes the baseline full run. Python guard changes do not execute in Flutter
timing commands.

```sh
flutter test --machine test/features/sessions/sessions_screen_test.dart test/features/shared/media_viewer_test.dart test/features/shared/attachment_picker_test.dart test/features/shared/chat_drop_zone_test.dart
flutter test --machine
```

Process wall includes launcher/hooks. File spans include loading and overlap
under parallel execution; their sum is neither wall nor CPU. No full-suite/CI
speedup is inferred from deleting one mount or one fixed pause.

| Focused package (seconds) | Before | After |
| --- | ---: | ---: |
| Wall samples | 12.596 / 13.503 / 13.401 | 12.990 / 12.744 / 12.980 |
| Median process wall, launcher/hooks included | 13.401 | 12.980 |
| Median child CPU | 29.543 | 29.107 |
| Median sum of file spans, loading included | 30.789 | 30.038 |
| Median loading sum | 19.036 | 18.576 |
| Median visible test-body sum | 11.728 | 11.439 |
| Passed / skipped / failed | 32 / 0 / 0 | 31 / 0 / 0 |
| Entry-point files | 4 | 4 |

Local median wall decreases **3.1%**, child CPU **1.5%**. Two pairs favor the
candidate; the first candidate is 3.1% slower than its control. Keep all samples:
this is a small local reduction, not a dependable full-suite/CI speedup.

The first full pair grows from **142.628 to 159.617s** (+11.9%), so a second
pair runs in reverse B/A order without changing runner settings. The changed
files account for 1.893s of the first pair's 133.680s increase in summed file
spans; most extra file time is in untouched suites. This does not establish
the cause or exclude indirect scheduling effects.

| Full run, chronological order | Process wall (s) | Child CPU (s) | File-span sum (s) | Loading sum (s) | Visible body sum (s) | Passed / skipped / failed |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| A1: before | 142.628 | 1142.658 | 1085.853 | 474.237 | 610.104 | 1922 / 4 / 0 |
| B1: after | 159.617 | 1184.090 | 1219.533 | 501.425 | 716.090 | 1921 / 4 / 0 |
| B2: after | 133.053 | 1063.151 | 1014.713 | 446.050 | 567.186 | 1921 / 4 / 0 |
| A2: before | 139.714 | 1129.042 | 1065.444 | 459.784 | 604.252 | 1922 / 4 / 0 |

The reverse pair favors the candidate by 6.661s. Across two observations per
state, mean wall is **141.171 -> 146.335s** (+3.7%), CPU
**1135.850 -> 1123.620s** (-1.1%) and file-span sum
**1075.649 -> 1117.123s**. Both states discover 268 test-process files. The same
candidate varies by 26.564s between full invocations; **no dependable full-suite
wall-time improvement is demonstrated**. Retain the smaller repeated setup and
explicit completion/budget checks with their modest local result, not a promise
of total CI acceleration. Two conflicting pairs do not establish a repeatable
overall speedup or regression.

Validation:

- Individual sessions (11), viewer (11), and shared ingest caller (9) checks pass
  before combined benchmarking. Six focused comparisons and four full commands
  pass. Outcome Counters differ only by the one explicitly merged file/full-name
  registration; every other result/skip multiplicity remains. All four native-DLL
  skip names/reasons match in all full runs. No baseline failure occurred or
  was used to excuse a failure after the change.
- Three structural audit scripts preserve the merged prefix/row assertion and
  reconstruct the other original cases from completion observers. Original
  callbacks, inputs, error guards, UI actions, real IO and cleanup remain; the
  only extra UI postcondition requires actual decoded pixels. Creation inside
  the real zone before the operation and the unchanged 2s value are checked
  separately. Green remaining tests alone are not the merge evidence.
- `flutter analyze`: no issues, including configured type/lint/unused checks.
  No separate unused-code checker is configured for Dart.
- `dart format --output=none --set-exit-if-changed lib test integration_test`:
  800 files, zero changes. `python3 scripts/test-policy.py` and all seven
  `test_test_policy.py` example tests pass, including the new timeout method
  regression. A local probe shows the baseline matcher misses the new form.
- `git diff --check` passes. All four final Dart files match their audited,
  benchmarked snapshots after both comparison scripts restore them. No unused
  imports, fixtures or helpers are created. Temporary Python bytecode is removed.
- Production, Rust, generated bindings, dependencies, CI configuration and
  environment files are unchanged. Native/integration runners are not run.

## Limits

These are scripted UI/platform-adapter tests with actual local image codecs and
file IO. Physical desktop dialogs/drop events, native transfer, authorization
and persistence keep their separate runners. Those implementations and their
existing tests are unchanged. New tests only exercise the expanded policy guard;
none assert that other tests were deleted.
