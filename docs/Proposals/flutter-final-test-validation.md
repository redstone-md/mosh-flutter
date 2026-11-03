# Final test-suite validation and review fixes

This closes the final-comparison and inline-Rust-policy findings from the full
PR audit. Earlier timing tables describe intermediate source revisions; they
remain historical evidence. The direct original-to-final comparison below is
the result for the complete cleanup.

Per-test removal evidence is in the [initial cleanup](test-suite-cleanup.md),
[UI ledger](flutter-ui-test-cleanup.md), [next-reductions audit](flutter-test-audit-2026-11-02.md)
and [ordered follow-ups](flutter-ordered-test-cleanup.md).

## Immutable sources and measurement protocol

- Original: `3b2b88eb9fc49081be28b98c375c52fd7948adae`.
- Final source: `5704f6af658fb2f7bdbcc93d89e71f117910a17b`.
- Later report commits change documentation only. Test, implementation and
  dependency trees match the measured final source.
- Identical command: `flutter test --machine --no-pub`. One dedicated clean
  detached worktree is switched between those commits. Same installed Flutter
  3.44.7 / Dart 3.12.2, package configuration, unchanged localization inputs,
  dependency/native-hook caches, default concurrency, timeouts and retries.
- One excluded warmup per state precedes six captures in A/B, B/A, A/B order.
  No own concurrent suites, compiler, analyzer or formatter run during captures.
  Other agents on this shared host remain an uncontrolled source of contention.
- No retry, selected favorable sample, global test timeout increase or runtime
  environment optimization is used. This is a local warm-cache comparison, not
  a cold-build or CI/hardware guarantee; CI pins Flutter 3.44.8.

Full process wall includes the launcher, hooks and runner. Child CPU is user plus
system CPU of completed descendants. File spans include loading and can overlap;
their sum is reported separately. Loading intervals and visible testStart to
testDone intervals (including lifecycle hooks) also overlap; they do not form a
wall-time decomposition. These sums are elapsed runner intervals, not CPU time.

| Capture, in execution order | Source | Passed / skipped / failed | Wall s | Child CPU s | Sum file spans s | Sum loading s | Sum visible test intervals s |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| full-a1 | Original | 2079 / 4 / 0 | 198.336 | 1431.176 | 1522.706 | 682.562 | 837.568 |
| full-b1 | Final | 1861 / 4 / 0 | 146.210 | 1120.201 | 1121.409 | 448.657 | 670.267 |
| full-b2 | Final | 1861 / 4 / 0 | 130.952 | 1074.759 | 1004.238 | 413.173 | 589.338 |
| full-a2 | Original | 2079 / 4 / 0 | 171.327 | 1341.714 | 1317.958 | 609.428 | 706.726 |
| full-a3 | Original | 2079 / 4 / 0 | 173.070 | 1361.252 | 1336.591 | 614.023 | 720.683 |
| full-b3 | Final | 1861 / 4 / 0 | 131.748 | 1083.647 | 1003.645 | 410.571 | 591.465 |
| Original median | — | — | 173.070 | 1361.252 | 1336.591 | 614.023 | 720.683 |
| Final median | — | — | 131.748 | 1083.647 | 1004.238 | 413.173 | 591.465 |

Median full wall falls **23.88%**; child CPU falls **20.39%**.
Sum of file spans falls **24.87%**. All three pairs favor the final source for wall and CPU.
Wall ranges: original **171.327–198.336 s**, final **130.952–146.210 s**.
Three samples per state and a shared host cannot establish an isolated causal
effect or a stable CI percentage. These are observations of the complete
original-to-final cleanup, not an incremental saving from the review fixes.

Discovery: **2079 → 1861 passed**, **311 → 217 runner files**, four unchanged
Windows DLL-gated skips, zero failures. Every timed run has exactly its state’s
warmup outcome Counter (relative file, full test path, result, skip reason and
multiplicity); cross-state skip identities/reasons also match. No baseline
failure was labelled pre-existing or excluded.

Excluded warmups (same complete command, both passed): original wall
**261.354 s**, CPU **1704.393 s**; final wall **181.607 s**, CPU **1211.489 s**.
The warmups are not included in any median or percentage above.

## Review fixes and contract evidence

| Finding | Decision and verification |
| --- | --- |
| Final original-to-final cost was not established | Direct complete comparison above replaces the intermediate performance claim. All captures, including regressions and excluded warmups, are retained locally. |
| Inline Rust tests in ordinary source modules escaped policy | Include annotated test functions and test-gated items while excluding unrelated production regions. Preserve the frozen baseline and reason/issue requirements. Lexer examples cover nested gates, attributes, raw/continued strings, comments, lifetimes and const-generic signatures. Fourteen policy methods and nineteen independent Git probes pass; no Rust runtime source changed. |
| CodeAnt: scanner waits cannot prove isolate completion | ACCEPT. With explicit user approval, add one optional typed decoder argument that defaults to the existing real decoder. Tests await that exact Future, retain actual QR decoding and the same scanner/camera lifetime, and assert a valid concurrent frame is dropped only while decoding. A held real negative decode makes the old fixed-wait strategy fail immediately with one decode instead of two. All seven cases remain; both fixed negative-frame sleeps are removed. |
| CodeAnt: historical six policy methods should say seven | DO NOT ACCEPT as a factual correction. The referenced commit `1f027781` has six methods. Qualify the historical sentence with its commit; current policy verification has fourteen methods. |
| CodeAnt: concurrent frame encryption may reorder delivery | ACCEPT as contract hardening; an actual backend reordering was not reproduced on the installed VM. Check sequence-to-decrypted-payload mapping, unique nonces and both direction bits independently of bridge arrival order. A private reversed-delivery probe rejects the old assertion and passes the new one; moving nonce increment past await still fails the new test with real AES-GCM. Capture remains concurrent. |
| CodeAnt: routed fixture omitted the production lock observer | ACCEPT. Install the existing observer, unmount before moving it to a replacement Navigator, reset its lock state and give the fixture ownership of router disposal. Remove two redundant caller disposals. New real-gate regressions protect protected/late popup removal, allowed call-device actions, replacement routing and explicit-container state preservation. The old helper fails the protected-popup assertion. |

No test is deleted by this review-fix portion. Three caller-visible route/lifetime
cases are added. Prior per-test DELETE/MERGE decisions and retained replacements
remain in the linked cleanup ledgers; green execution is not evidence that a
deletion is safe. Independent reviewers checked the fixes and preservation
proofs separately from the runtime comparison.

GitHub has no CodeAnt inline review threads for these four suggestions; they are
general PR nitpicks. No thread was falsely marked resolved.

## Verification and limits

- Routed fixture consumers: 524 passed, no skips, across 53 runner owners, both
  ordinary order and random seed 42. Exact outcome Counters match; all 521 old
  identities remain, with only three new lock cases.
- Scanner: device-link selection 50 passed across six owners; scanner-only
  seed 42 passes all seven cases with the same exact Counter.
- Voice orchestrator: 25 passed, plus the private ordering/nonce mutation probes.
- `flutter analyze`: no issues, including existing unused declaration/import
  checks. No separate unused-code tool is configured.
- `dart format --output=none --set-exit-if-changed lib test integration_test`:
  822 files, zero changed. `git diff --check` and policy guard pass.
- `python3 -B -m unittest discover -s scripts -p test_test_policy.py`: 14 methods
  pass; independent policy review includes 19 allowed/forbidden real-Git probes.
- Rust/native runtime, bindings and schemas do not change. These checks do not
  claim a new Windows/macOS/device/live-native execution. Four historical
  Windows DLL-gated skips remain explicit.
- Only production edit is the approved scanner decoder seam, with the same real
  implementation by default. No further production behavior change is intended.
  The lexical policy guard does not expand macros or resolve arbitrary aliases;
  its documented manual-review limitations still apply.

Raw stdout/stderr, revision pins, process timing records, exact-outcome Counters,
protocol, harness and reviewer hashes are retained locally under
`.git/pr114-fixes/`. The published table contains every timed capture; no discarded
sample is concealed. Baseline warmup and final warmup are reported separately.

## Files changed by this review follow-up

- Approved production seam: `lib/src/features/device_link/device_qr_scanner.dart`.
- Scanner contracts: `test/features/device_link/device_qr_scanner_test.dart`.
- Route fixture/lifetime: `test/support/pump_route.dart`,
  `test/features/lock/pump_route_lock_test.dart`,
  `test/features/voice_call/android_call_presentation_test.dart`,
  `test/features/voice_call/voice_call_navigation_test.dart`.
- Voice nonce oracle: `test/features/voice_call/voice_call_orchestrator_test.dart`.
- Policy: `.gitignore`, `scripts/test-policy.py`, `scripts/rust-test-policy.py`,
  `scripts/test_test_policy.py`.
- Reports/policy docs: `docs/testing.md`, this report,
  `docs/Proposals/test-suite-cleanup.md`,
  `docs/Proposals/flutter-scanner-test-cleanup.md`,
  `docs/Proposals/flutter-test-audit-2026-11-02.md`,
  `docs/Proposals/flutter-test-runtime.md`.
