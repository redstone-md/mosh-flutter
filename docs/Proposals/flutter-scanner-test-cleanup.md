# Scanner synchronization cleanup

Historical stage: the measurements and retained waits below describe the first
scanner cleanup. The [review follow-up](flutter-final-test-validation.md) removes
both remaining negative-frame sleeps by observing the exact real decoder Future
through the explicitly approved optional seam. All seven contracts remain; the
default production decoder is unchanged. No new scanner-only speedup is claimed.

Baseline: `501c06e20f07a0f52850a923ffee546e7a6a388e`. Scope:
`test/features/device_link/device_qr_scanner_test.dart` and its only camera fake,
`test/support/scanner_platform.dart`. Production, dependencies, CI, native
authorization and test timing defaults are unchanged. All seven tests remain.

## Contracts and synchronization

The previous `_settle` slept three times for 100ms and pumped after each pause.
Seven `_open` calls plus twelve other invocations imposed **5.7s** of real
delays per successful suite run. Most calls were merely waiting for fake camera
microtasks, UI transitions or a successful scanner return.

Camera-only paths now use the existing widget clock and `pumpAndSettle`.
The three tests that actually decode frames run their setup and stream listener
in `runAsync`, allowing real isolate completion to progress. Their route callback
signals a test-owned completion only after delivering the actual Navigator
result. Successful scans await that completion and finish route transitions.
The existing camera fake exposes read-only first-stream and first-release
futures; frames are submitted only after the listener is set up, and disposal
checks await the actual platform call. These signals do not manufacture QR
results, replace the decoder or change camera counters/error behavior.

The installed camera implementation discards the async frame callback's return
value. The scanner does not expose completion when decoding produces no URI.
Therefore the two historical waits after blank/broken frames remain unchanged
at 3 x 100ms each, now narrowly named `_finishNegativeFrame`. Their callers
already execute in the real async zone. Fixed delays decrease **5.7s -> 0.6s**;
this removes 5.1s of deliberate waiting, not a promise of identical process-wall
or full-suite savings. The remaining 0.6s is retained synchronization debt, not
a timing contract or an approved pattern for new tests.

Flutter's [runAsync documentation](https://api.flutter.dev/flutter/flutter_test/WidgetTester/runAsync.html)
explains why isolate work needs real async execution and a completion future;
the installed binding and camera sources were also inspected. No polling,
extra timeout/retry, global motion changes or production test hooks are added.

## Case ledger

All names are full paths in `test/features/device_link/device_qr_scanner_test.dart`,
without describe/group prefixes. There are no DELETE or MERGE decisions.

| Full test path | Protected contract | Decision | Evidence |
| --- | --- | --- | --- |
| `camera ignores frames without a QR and returns one URI, then releases camera` | Blank input does not return; repeated valid frames return one URI and release the camera. | REWRITE synchronization | Keep blank and repeated padded QR frames, URI/list/route assertions and exact release/start comparison. Await stream setup, actual route result and first native release; retain the blank-frame wait. |
| `a broken frame does not stop scanning` | Malformed planes cannot wedge the decoder gate. | REWRITE synchronization | Read `b2c5505f` / IVO-158. Keep the short plane followed by a real QR and the original URI assertion. Retain its negative-frame wait; successful decoding awaits the actual result. |
| `leaving while the camera opens closes it; return reopens it` | Pending open closes in background, then resumes exactly once. | REWRITE synchronization | Read `b2c5505f`. Keep the held opening completer, inactive/resumed order, `(1,1)` counts, absence of spurious error, second start and decoded URI. Await first native release and the first stream, which correctly belongs to the resumed camera. |
| `camera stops in background and restarts on return; fallback cancels scan` | Foreground lifecycle releases/restarts; fallback returns null and releases again. | REWRITE synchronization | Keep every lifecycle event, count, fallback tap and result assertion; fake operations and transitions use managed widget frames. |
| `a camera that cannot stream is released and reported` | Stream setup failure reports unavailable and releases its controller. | REWRITE setup wait | Read `2d1a5601` / IVO-158. Native exception, unavailable wording and `(1,1)` assertion remain; no decoder work needs a real delay. |
| `denied permission keeps the image/link alternative available` | Permission denial leaves fallback usable and error-free. | REWRITE synchronization | Keep the exact platform error, displayed wording, fallback tap, null result and exception check. No decode task runs. |
| `no camera keeps the image/link alternative available` | Missing hardware leaves fallback usable and error-free. | REWRITE synchronization | Keep the empty camera list and all original assertions; fake operation/UI completion replaces fixed sleeps. |

The existing QR frame generators, real `decodeQrFrame`/zxing2 computation,
native URI validation and scanner implementation are unchanged. `ScannerPlatform`
has no consumers outside this suite. Its extra futures are passive observations
of existing operations; the first-stream future suffices for the three decode
tests because the interrupted first camera in the pending-open case never streams.

## Measurement protocol and checks

Raw commands, JSON, stderr, wall and child CPU records live locally in
`.git/test-audit/scanner/`. The same workspace and warm dependency/native-hook
caches are used, without concurrent suites, analyzers or audit compilers during
timed commands. Focused controls/candidates run A/B, B/A, A/B; both owned files
are restored byte-for-byte from the baseline/saved candidate and protected by
`finally` restoration.

```sh
flutter test test/features/device_link/device_qr_scanner_test.dart --reporter json
flutter test --reporter json
```

A source AST audit separately compares the seven callback paths after only the
documented synchronization substitutions. Original assertions, QR bytes,
hardware factories, lifecycle order and the stream failure branch stay intact.
The negative delay expression and its three-iteration bound match baseline.
Outcome Counters compare file/full-name/result/skip identities and multiplicity.
A green remaining suite alone is not the preservation evidence.

| Focused measurement (seconds) | Before | After |
| --- | ---: | ---: |
| Wall samples | 18.802 / 15.502 / 15.842 | 9.740 / 9.996 / 9.895 |
| Median process wall, launcher/hooks included | 15.842 | 9.895 |
| Median child CPU | 16.762 | 14.769 |
| Median file span, loading included | 13.298 | 7.652 |
| Median visible test-body sum | 8.537 | 3.002 |
| Deliberate real pauses per successful suite | 5.700 | 0.600 |
| Passed / skipped / failed | 7 / 0 / 0 | 7 / 0 / 0 |

All three pairs favor the candidate for wall and CPU: local median wall
decreases **37.5%**, CPU **11.9%**. The initial pilot passed all seven tests in
11.263s; it is retained separately and excluded from paired medians. The first
control preceded the baseline full run; the two follow-up pairs used B/A, A/B
order without other timed jobs running concurrently.

| Full command (seconds; one observation per state) | Before | After |
| --- | ---: | ---: |
| Total process wall, launcher/hooks included | 163.847 | 156.080 |
| Completed-child CPU | 1319.614 | 1257.002 |
| Sum of file spans, loading included | 1253.104 | 1192.319 |
| Sum of loading spans | 548.472 | 527.492 |
| Sum of visible test-body spans | 702.781 | 663.033 |
| Passed / skipped / failed | 1925 / 4 / 0 | 1925 / 4 / 0 |
| Discovered test-process files | 268 | 268 |

This full pair completed 7.767s sooner. One pair does not establish a dependable
complete-suite/CI speedup, and changes in untouched-file timings cannot all be
attributed to this module. File spans start at loading and finish at the suite's
last test completion; their sum overlaps under parallel execution and is neither
wall nor CPU time. Visible body spans exclude hidden loading/setup events.

Validation:

- All six focused benchmark runs and both full runs pass. Exact file/full-name/
  result/skip Counters match, including multiplicity. All four full-suite skips
  retain their original Windows native DLL gates; no baseline failures occurred.
- Source audit preserves every original assertion, frame byte generator,
  hardware/error factory, lifecycle order and actual Navigator result callback.
  The only camera-fake changes are passive first-stream/first-dispose signals.
- `flutter analyze`: no issues, including existing lint/type/unused checks.
- `dart format --output=none --set-exit-if-changed lib test integration_test`:
  800 files, zero changes. `python3 scripts/test-policy.py` and `git diff --check`
  pass; guard rules and timing/skip defaults are unchanged.
- Both candidate files match their saved bytes after all source controls.
  Production, Rust, bindings, dependencies, CI and environment files are unchanged.

## Limits

The two no-result decode waits remain historical debt because their completion
cannot be observed here without a production interface change. No such change
is permitted in this cleanup. These are mocked camera-hardware widget tests;
physical Android cameras and native device authorization need their existing
separate runners.
