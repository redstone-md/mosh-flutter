# Attachment preview synchronization cleanup

Baseline: `fcdf28cf4195eaf4838fadce0e6648eb44d0d2f5`. Scope:
`test/features/conversation/attachment_preview_arrival_test.dart`. All six tests
remain; production, fixtures in other suites, dependencies, timing defaults,
native gates and CI are unchanged.

## Contracts and change

Read the implementation in `attachment_card_branches.dart` and
`attachment_preview_image.dart`, ADR 0041, and the introducing regression commit
`d0ea73b6` (PR #58, closes #56). These are useful compatibility, dimension-limit
and fallback tests. No DELETE or MERGE is justified here.

The original synchronization executed two unconditional loops of 20 x 30ms real
sleeps plus four single 30ms sleeps: **1.32s** of deliberate pauses. The loops
also pumped 100ms of widget time on every iteration; that simulated time is not
another four seconds of real waiting.

The existing mount helper now runs setup and image completion inside `runAsync`.
It awaits `precacheImage` for each mounted Image's exact provider, then pumps the
loaded/error UI. Original, clear-preview and miniature providers in the fallback
tree are included. ResizeImage and the custom pre-decode dimension guards stay
intact; the assertion-only `_provider` unwrap helper is not used for loading.
No replacement polling, timeout/retry override, fake decoder or new abstraction
is introduced. The miniature-only first mount in the arrival test now also waits
for its actual image instead of merely asserting the provider's type.

`precacheImage` completes on success or error. Its error callback handles only
the extra cache observer; the Image's existing errorBuilder still receives the
error and its UI remains asserted. Expected guard, unsupported-codec and missing
file failures therefore complete without arbitrary sleeps. Flutter's existing
cache observer releases its listener after the subsequent frame (immediately on
error). Real file IO, codecs, directory cleanup and Download interactions remain.

## Case ledger

Every path below is a full root-level test name in
`test/features/conversation/attachment_preview_arrival_test.dart` (no groups).

| Full test path | Protected contract | Decision | Evidence |
| --- | --- | --- | --- |
| `a legacy portrait miniature still displays after upgrade` | Legacy 320 x 480 portraits remain readable. | REWRITE synchronization | Keep the actual encoded JPEG, decoded height 480, absence of broken-image UI and exception check. |
| `an inline miniature with excessive dimensions is not decoded` | A small encoded payload cannot bypass the intrinsic dimension limit. | REWRITE synchronization | Keep the 1 x 4096 PNG, base64 byte-budget assertion, broken-image result and exception check. Await the actual guarded provider's failure. |
| `a small JPEG with oversized dimensions falls back before pixel decoding` | An auxiliary preview with an excessive edge falls back to the inline miniature. | REWRITE synchronization | Keep the 320 x 2048 JPEG below 128 KiB, real file and decoded 24 x 16 miniature assertions. Wait for the wrapped file provider and miniature, replacing the 20-iteration loop. |
| `an unsupported original displays its clear JPEG before the miniature` | Failed original decoding prefers the available clear preview over the miniature. | REWRITE synchronization | Keep actual TIFF/JPEG files, their sizes, preview path, absence of miniature/Download and exception assertions. Wait for the real providers rather than 20 fixed pauses. |
| `the clear preview replaces the miniature without completing the original` | Preview arrival changes the image without marking the original available or starting a download. | REWRITE synchronization | Keep both mounts, provider/path checks, empty downloads before the tap, Download control, exact resulting attachment ID and exception check. |
| `a missing clear preview keeps the miniature visible` | Missing cached files preserve a usable miniature and filename. | REWRITE synchronization | Keep the nonexistent path, miniature/filename assertions, absence of broken-image UI and exception check. |

A local AST audit compares all six callback statement sequences against the
immutable baseline after removing only the exact historical waits. Names/order,
image sizes/bytes, assertions, IO, taps and teardown match. The card mount,
descriptor and other helper tokens are unchanged; the audit separately checks
the real async zone, exact provider and final UI settling. This source evidence
is separate from the remaining suite being green. Audit scripts are inspection
artifacts, not new tests that assert the cleanup itself.

## Measurement and verification

Raw JSON, stderr, source snapshots, audit scripts and process wall/child CPU
records live locally in `.git/test-audit/attachment-preview/`. Same commands and
workspace, warm caches, serial comparisons A/B, B/A, A/B. No other suite, analyzer
or audit compiler is launched by this task during timed runs. Baseline/candidate
source changes use byte checks and `finally` restoration of this one owned file.

```sh
flutter test --machine test/features/conversation/attachment_preview_arrival_test.dart
flutter test --machine
```

| Focused measurement (seconds) | Before | After |
| --- | ---: | ---: |
| Wall samples | 10.008 / 10.016 / 9.488 | 9.203 / 8.980 / 8.107 |
| Median process wall, launcher/hooks included | 10.008 | 8.980 |
| Median child CPU | 13.546 | 13.948 |
| Median file span, loading included | 7.828 | 6.733 |
| Median loading span | 4.547 | 4.605 |
| Median visible test-body sum | 3.267 | 2.119 |
| Deliberate real pauses per successful suite | 1.320 | 0 |
| Passed / skipped / failed | 6 / 0 / 0 | 6 / 0 / 0 |

All three pairs favor the candidate for wall. Local median process wall decreases
**10.3%**; the visible body sum decreases **35.1%**. CPU does not improve: its
median increases **3.0%**. This change removes waiting, not codec work. The initial
control (10.899s) and pilot (8.175s) remain separate from the paired medians; both
passed all six tests. The pilot used an external 60s diagnostic deadline, with no
test timeout changes.

An unrelated Flutter job on the shared host overlapped at least part of the
baseline and focused measurements. It was neither started nor modified by this
task. Host load is not controlled; the full comparison is descriptive, not
evidence of a dependable CI speedup. File spans include loading and end at the
last completion in each suite; their sum overlaps in parallel execution and is
neither process wall nor CPU time.

| Full command (seconds; one observation per state) | Before | After |
| --- | ---: | ---: |
| Total process wall, launcher/hooks included | 148.320 | 142.479 |
| Completed-child CPU | 1175.031 | 1121.424 |
| Sum of file spans, loading included | 1125.564 | 1084.816 |
| Sum of loading spans | 497.942 | 477.297 |
| Sum of visible test-body spans | 626.013 | 605.943 |
| Passed / skipped / failed | 1925 / 4 / 0 | 1925 / 4 / 0 |
| Discovered test-process files | 268 | 268 |

This full pair finishes 5.841s sooner. Changes in untouched-file timings cannot
all be attributed to removing these pauses; no stable full-suite speedup is
claimed from this single pair and uncontrolled host load.

Validation:

- All six paired focused runs, the pilot, initial control and both full runs
  pass. File/full-name/result/skip Counters match exactly, including multiplicity.
  The four native-DLL gates retain the same test names and skip reasons. No
  baseline failure occurred; no failure is dismissed as pre-existing.
- The source AST audit preserves every original assertion, input, file operation,
  teardown and download interaction. All six regression paths remain; no deletion
  or claimed replacement relies merely on a green reduced suite.
- `flutter analyze`: no issues, including existing lint/type/unused checks. No
  separate unused-code checker is configured for Dart.
- `dart format --output=none --set-exit-if-changed lib test integration_test`:
  800 files, zero changes. `python3 scripts/test-policy.py` and `git diff --check`
  pass. Guard rules and timing/skip defaults are unchanged.
- The final test file matches its saved candidate bytes after all controls.
  Production, Rust, bindings, dependencies, CI and environment files are unchanged.

## Limits

These tests exercise Flutter's actual image pipeline with local files, not native
transfer, authentication, encrypted persistence or physical-device delivery.
Those contracts retain their existing suites. Removing fixed waits improves
synchronization and eliminates 1.32s of intentional delay; full process wall
savings need measurement and cannot be inferred from that amount alone.
