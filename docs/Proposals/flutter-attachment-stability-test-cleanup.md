# Attachment stability synchronization cleanup

Baseline: `2ff176f2ee3140e08b844ccdb54b759630b4fd66`. Scope:
`test/features/conversation/attachment_card_stability_test.dart`. All five tests
remain. No production, dependency, CI, global timing or environment change.

## Contract and synchronization

Read `f4c85d14` (IVO-27/21/19), `7b4dce09` (IVO-27), ADR 0041 and the current
attachment card, preview providers and `ConversationAttachment`. The tests
protect header-based sizing before decode, available bubble width, bounds for
portrait/panorama/unknown images, immediate reuse after reopening and stable
transfer-control/time geometry. None is a justified deletion.

The old `_decode` ran ten unconditional 20ms real sleeps and ten 50ms widget
pumps. Four calls imposed **0.8s** of deliberate pauses and forty synchronization
pumps. The additional two seconds of advanced widget time are simulated, not
two more seconds of real waiting.

The existing helper becomes `_pumpDecoded`: it mounts the same card in
`runAsync`, awaits `precacheImage` for each mounted Image's exact provider, then
pumps the completed UI once. ResizeImage and intrinsic-dimension guards remain
intact. Expected errors complete the cache observer while still reaching the
Image's errorBuilder. No raw/unwrapped substitute, fake codec, polling, new
timeout or retry is introduced. Four existing waits become four completion
waits and four final pumps, avoiding thirty-six synchronization pumps.

Starting native decode inside the real zone matters. A helper-only prototype
that awaited existing fake-zone work never finished its first case and was
stopped by an external 45s diagnostic deadline. Its raw log and source are kept
as `rejected-helper-only.*`, outside successful measurements. The cancellation's
sink teardown error is not a baseline failure or a passing result. No diagnostic
deadline is added to tests. The successful frame-observer pilot is also separate
from paired timing samples.

The three before-decode observations move to synchronous first-post-frame
callbacks, registered before the card is mounted. This observes layout before
native completion can rebuild it, instead of moving assertions after loading.
The cold miniature additionally asserts `RawImage.image == null` at its initial
size measurement. That case explicitly clears the test binding's image cache
and live-image map before mounting, so the cold-load precondition does not depend
on test order. Other cases, including the return/cache-hit check, do not clear
the cache. Existing post-decode comparisons follow actual completion.
The malformed image still checks unchanged height, broken-image UI and no
uncaught exception. Card parameters, original bytes/sizes, real clear-file IO
and teardown are retained.

The return-to-chat test only uses the completion helper for its initial load.
Its away/reopen calls and immediate RawImage assertion remain unchanged on the
original fake-clock path, with no wait after reopening. Narrow-bubble and
footer/progress cases remain token-identical. No new helper abstraction is added;
the existing local helper now owns the four repeated mount/completion sequences.

## Case ledger

Every name is a full root-level path in
`test/features/conversation/attachment_card_stability_test.dart` (no groups).
There are no DELETE or MERGE decisions.

| Full test path | Protected contract | Decision | Evidence |
| --- | --- | --- | --- |
| `the preview reserves its final height before any decode` | Initial reserved geometry survives miniature and clear-file decode. | REWRITE synchronization | Same images, transfer states and size comparisons. Initial measurements now run in the first layout frame; the cold-image-null precondition proves the initial observation is not made after decode. Real JPEG creation and cleanup remain. |
| `a narrower bubble keeps the media aspect ratio` | Actual width 240 yields a 240 x 160 preview. | KEEP | Complete callback unchanged; regression `7b4dce09`. |
| `portrait and unknown sizes stay within the preview bounds` | Portrait/panorama bounds and unknown-height stability on decode error. | REWRITE synchronization | Portrait/panorama mounts and assertions unchanged. Unknown height is captured in its initial frame; actual error completion precedes the original size/icon/exception assertions. |
| `a returning chat shows its decoded miniature in the first frame` | Reconstructed descriptors reuse decoded miniature data immediately. | REWRITE initial-load wait | Same descriptor recreation, away/reopen sequence and immediate RawImage check. No precache, settle or real wait is inserted on return. |
| `time keeps the cancel button in place and stays off progress` | Adding the timestamp preserves controls and aligns with progress. | KEEP | Complete callback unchanged, including relative rects, percent, timestamp and exception assertion; regression `f4c85d14`. |

A local AST audit reconstructs the original five callbacks from the four new
mount/completion calls and first-frame observers. Every original fixture,
initial observation, postcondition, IO/cleanup operation and return-frame check
is retained in order. It separately checks the cold-cache setup and new
cold-image precondition, unchanged helpers/imports and exact provider completion.
This source evidence
does not depend solely on the remaining suite being green. Inspection scripts
stay local, not as new tests that merely confirm the cleanup.

## Measurement and checks

Raw JSON, stderr, snapshots, wall/child CPU data and AST tools live locally in
`.git/test-audit/stability/`. Same workspace and warm caches; focused comparisons
run A/B, B/A, A/B. No other suite, analyzer or audit compiler is launched by this
task during timed runs. Only the owned test file is swapped, with byte checks
and `finally` restoration. The preliminary control precedes the baseline full
run; the final six focused samples follow the explicit cold-cache setup. Full
process wall includes launcher/hooks. Summed file spans include
loading and overlap under parallel execution; their sum is neither wall nor CPU.

```sh
flutter test --machine test/features/conversation/attachment_card_stability_test.dart
flutter test --machine
```

| Final focused measurement (seconds) | Before | After |
| --- | ---: | ---: |
| Wall samples | 8.621 / 8.293 / 8.058 | 7.523 / 7.777 / 7.075 |
| Median process wall, launcher/hooks included | 8.293 | 7.523 |
| Median child CPU | 12.103 | 10.981 |
| Median file span, loading included | 6.199 | 5.385 |
| Median loading span | 3.900 | 3.905 |
| Median visible test-body sum | 2.293 | 1.473 |
| Deliberate real pauses per successful suite | 0.800 | 0 |
| Synchronization pumps after those pauses/completions | 40 | 4 |
| Passed / skipped / failed | 5 / 0 / 0 | 5 / 0 / 0 |

All three final pairs favor the candidate for wall and CPU. Local median wall
decreases **9.3%**, child CPU **9.3%** and visible body sum **35.8%**. This is not
a promise of identical full-suite savings; timing changes in untouched files
cannot all be attributed to this module.

An earlier paired cohort, before making cold-cache setup explicit, is preserved
in `pre-cold/`: median wall **8.197 -> 8.162s**, CPU **11.051 -> 12.298s**, body
sum **2.364 -> 1.616s**. That cohort did not demonstrate a whole-file gain and
had higher CPU. The setup was corrected for order independence, not to tune
timings; favorable final CPU samples are not attributed to cache clearing.
The successful pilot (8.124s, before the helper rename and cold-cache setup) is
also excluded from final paired medians. Both external diagnostic deadlines
were 45s and never became test timeout overrides.

| Full command (seconds; one observation per state) | Before | After |
| --- | ---: | ---: |
| Total process wall, launcher/hooks included | 151.376 | 151.130 |
| Completed-child CPU | 1203.632 | 1213.143 |
| Sum of file spans, loading included | 1153.944 | 1147.978 |
| Sum of loading spans | 513.943 | 501.179 |
| Sum of visible test-body spans | 638.215 | 645.008 |
| Passed / skipped / failed | 1922 / 4 / 0 | 1922 / 4 / 0 |
| Discovered test-process files | 268 | 268 |

Full wall changes by only -0.247s (-0.2%), while child CPU increases 0.8%.
**No dependable full-suite speedup is demonstrated.** Keep the local result
separate from total runtime: this removes deliberate pauses and gives actual
completion/first-frame observations, not a claim that every whole-suite run or
CI job becomes faster.

Validation:

- All six final focused comparisons and both full commands pass with exact
  file/full-name/result/skip Counter equality, including multiplicity. All five
  regression paths remain. The four native-DLL skip names and reasons match;
  no baseline failures occurred or were used to excuse a candidate failure.
- Existing cases also pass with `--test-randomize-ordering-seed=42` and `=7`:
  the cold-size case runs third and last, respectively. No new verification
  test or permanent randomization/configuration is introduced.
- AST inspection reconstructs original case sequences and checks first-frame
  observation before mount completion, all actual provider wrappers, the real
  async zone and the unchanged immediate return/cache-hit path. All original
  assertions, data, IO/cleanup and footer geometry remain.
- `flutter analyze`: no issues, including configured lint/type/unused checks.
  No separate unused-code checker is configured for Dart.
- `dart format --output=none --set-exit-if-changed lib test integration_test`:
  800 files, zero changes. `python3 scripts/test-policy.py` and `git diff --check`
  pass. Final test bytes match the audited, benchmarked candidate after all
  source controls. No unused imports or orphan fixtures/helpers are introduced.
- Production, Rust, generated bindings, dependencies, CI and environment files
  are unchanged. Native/integration runners are not run in this test-only change.

## Limits

These use the actual Flutter image pipeline and local files, with scripted
attachment state. Native transfer, encrypted persistence and physical-device
behavior retain their existing separate suites. Global timing, policy gates,
network/live exceptions and default timeouts/retries are unchanged.
