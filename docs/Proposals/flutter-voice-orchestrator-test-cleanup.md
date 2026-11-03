# Voice orchestrator test synchronization

Baseline: `5fa08c588c78a399cd93052af07a14164ca03bb9` on
`test/prune-low-value-suites`; clean working tree before this change.
Scope: `test/features/voice_call/voice_call_orchestrator_test.dart` and its
private `voice_call_orchestrator_support.dart` part. All **9 cases remain**.
No production declaration or test case is deleted.

## Contract review

Read the orchestrator, `CallAudioSession`, `drainCallFrames`, frame crypto,
capture/playback interfaces, scripted bridge, Architecture, glossary and call
ADRs 0043/0044. Reviewed the originating test history (`e8e2f0e5`) and the
`4ee0ec2e` change that preserves navigation lifetimes and prevents reporting an
unattached microphone as muted. Keep crypto, both directions, sequencing,
reordering, mute, cancellation, overlapping reads and setup-failure behavior.

The old suite has ten `Future.delayed` expressions; the direction loop executes
one twice. They impose **1.04s** of sleeps per successful run. Its capture fake
also schedules each supplied frame on a 30ms timer. Neither this fake's cadence
nor an arbitrary real waiting margin is a production audio timing contract.
The actual session still owns its unchanged 20ms periodic drain.

Seven asynchronous cases use `fake_async` with ordinary `test` registrations;
the two cases without waits remain unchanged. Production timer ticks are
advanced explicitly, including **three held ticks** and **three post-detach
ticks** for negative assertions. `flushMicrotasks` completes the original
async crypto/bridge work; no encoder, decoder, AES-GCM operation or bridge
payload is stubbed out. One private `_withClock` helper, used by all seven
cases, drives their existing async bodies, propagates their original failures,
requires completion and rejects leaked timers. It prevents unresolved awaits
from silently skipping assertions. See the package's
[clock documentation](https://pub.dev/packages/fake_async) and
[microtask semantics](https://pub.dev/documentation/fake_async/latest/fake_async/FakeAsync/flushMicrotasks.html).
Context7 was queried first; its results did not cover these APIs, so the official
documentation and installed Flutter/cryptography/fake_async sources were read.

The existing capture fake now emits its supplied frames explicitly. Sequence
callbacks arrive consecutively before crypto futures finish, retaining both
caller/callee bits, decoded payloads and sequence assertions. Its old timer,
index, scheduling/start methods and now-unused `dart:async` import are removed.
All consumers are the four construction sites in this one test library.

The previous late-callback test awaited detach, which cancelled the fake's timer
and prevented the callback from running at all. Now it confirms the capture was
stopped, explicitly invokes the retained callback, flushes crypto work and
requires that no frame was sent. This strengthens the existing case.

## Case ledger

File: `test/features/voice_call/voice_call_orchestrator_test.dart`.
Every full path includes its actual `voice_call_orchestrator` group prefix.

| Full describe/test path | Contract | Decision and evidence |
| --- | --- | --- |
| `voice_call_orchestrator / attach imports the call key and starts the poll` | Attach activates periodic bridge reads. | REWRITE clock: advance the first production interval instead of sleeping 60ms; keep the read assertion and detach. |
| `voice_call_orchestrator / toggleMute does not claim an unattached microphone is muted` | Unattached microphone never reports muted (`4ee0ec2e`). | KEEP unchanged. |
| `voice_call_orchestrator / a captured frame while muted is not sent, and is sent when unmuted` | Muted callback sends nothing; unmuted callback sends the right session/call and decodable original payload. | REWRITE delivery/clock: explicitly fire both supplied callbacks and flush crypto, retaining every original assertion. |
| `voice_call_orchestrator / seq increments per frame and the direction bit is applied` | Three distinct sequence values and correct high bit for caller and callee. | REWRITE delivery/clock: deliver the same three frames consecutively; retain real decryption, payload inputs, both directions and exact sequence/bit assertions. |
| `voice_call_orchestrator / drained frames surface reordered to playback` | Real encrypted 3/1/2 input reaches playback as 1/2/3 with the original payloads. | REWRITE clock: advance the real polling interval virtually; retain encryption, decryption and all three sequence/payload comparisons. |
| `voice_call_orchestrator / the draining guard drops a tick while a drain is in flight` | Held read blocks overlapping drains; releasing it permits the next drain. | REWRITE clock: keep hold/release and original counts; elapse three ticks, release/flush, then elapse another tick. |
| `voice_call_orchestrator / detach cancels the poll and stops capture/playback` | Detach releases both handles and prevents further reads. | REWRITE clock: keep initial positive read, stopped flags and unchanged count after three more virtual ticks. |
| `voice_call_orchestrator / a capture onFrame firing after detach is a no-op` | An already queued capture callback cannot send media after cancellation. | REWRITE fixture: actually fire after confirming stop; keep original no-send assertion and add the stopped precondition. |
| `voice_call_orchestrator / setup failure calls onError + endCall(setup_failed)` | Playback startup error is reported and terminates signaling with the proper reason. | KEEP unchanged. |

No DELETE or MERGE decisions. An AST audit removes only the audited old waits
or new clock advances/flushes/frame triggers/stopped precondition, then compares the remaining
case bodies token-for-token. All original assertions, attach arguments, keys,
payloads, directions, crypto paths, holds/releases, stops and registration order
match. Unrelated support declarations, including `_orchestrator`, stay exact.

## Independent fault checks

Diagnostic copies in `.git/test-audit/voice-orchestrator/` redirect only the test
import to copied orchestrator/session sources. Production files are untouched.
The AST generator requires each selected guard to match exactly once.

- Remove both cancellation checks from the copied `_onFrame`/`_send`: the old
  late-callback case still passes; the new case fails its original empty-frame
  assertion because an encrypted frame was actually sent.
- Remove the copied `_draining` guard: the new held-read case fails its exact
  count assertion, observing three reads instead of one.

These deliberate failures establish that the new synchronization exercises the
failure classes. They are not baseline failures and are excluded from timing
samples. Diagnostic source swaps restore both candidate files byte-for-byte.
No test is added merely to confirm deletion of another test.

A preliminary prototype added async detach through `addTearDown` to the owner
helper. Its first widget case did not finish and was interrupted (exit 130).
Removing only that new cleanup made all nine cases pass; the original explicit
detaches and helper are retained. Rejected sources/logs are preserved as
`rejected-widget-zone-*`. No timeout or retry was increased. A tooling compile
error from the installed analyzer's renamed class-name accessor is recorded
separately; it occurred before any tracked edit or test execution.

## Measurements and checks

Identical commands for each source state:

```sh
flutter test --machine test/features/voice_call/voice_call_orchestrator_test.dart
flutter test --machine
```

Serial invocations, ordinary warm caches and default runner settings; no own
analyzer, diagnostic/compiler or other test command overlaps timed commands.
The immutable baseline, candidate sources, commands, JSON events, wall/child-CPU
times, exit statuses and swap scripts are in `.git/test-audit/voice-orchestrator/`.
Both owned files are checked before swaps and restored in `finally` blocks.

The first complete prototype uses `testWidgets` clocks. Its three-pair medians
are 7.521 -> 7.483s wall (-0.5%), 9.663 -> 10.314s CPU (+6.7%), file spans
5.334 -> 5.249s, loading 4.184 -> 4.784s and bodies 1.142 -> 0.459s. Raw wall
controls: 7.521/7.776/7.470s; candidates: 7.669/7.483/6.836s, ordered A/B,
B/A, A/B. The first successful corrected check (`check-without-teardown`,
7.669s) is included as `after-1`, not discarded as warm-up. A full integration
comparison passes 1921 tests plus the same four skips, wall 208.261 -> 185.956s,
CPU 1203.747 -> 1190.290s and file-span sum 1591.989 -> 1418.515s. That single
full pair does not establish a speedup caused by the change. The widget-clock
variant is superseded because its focused CPU cost increases and wall barely
improves.

The first pure-clock comparison uses fresh A/B, B/A, A/B controls. A draft AST
generator duplicated an `async` keyword; formatting/compilation rejected it
before any case ran (recorded as `rejected-pure-parse.*`). Its preceding
successful control, 7.785s, is retained as `pure-before-1`. The generator was
corrected and now validates parsing before writing its output. That cohort's
wall controls are 7.785/7.776/7.421s and candidates 6.541/6.781/6.632s;
medians are 7.776 -> 6.632s wall, 10.422 -> 10.070s CPU, 5.445 -> 4.411s
file spans, 4.294 -> 4.283s loading and 1.145 -> 0.129s bodies.

The fault logs then exposed a secondary `Future.then` error: the success
callback inferred `bool` while the error callback returned void. Explicit
`then<void>` fixes the helper's error propagation. Both faults are rerun:
each candidate fails for its original contract assertion, without the
secondary type error. Fresh final pairs measure this exact helper revision;
earlier samples and sources (`pure-untyped-support.dart`) remain available.

| Final focused pair | Before process wall (s) | After process wall (s) | Order |
| --- | ---: | ---: | --- |
| 1 | 7.528 | 5.996 | A/B |
| 2 | 7.061 | 6.164 | B/A |
| 3 | 7.055 | 6.445 | A/B |

| Focused median, 3 samples/state | Before (s) | After (s) |
| --- | ---: | ---: |
| Whole process wall, launcher/hooks included | 7.061 | 6.164 |
| Child CPU | 9.468 | 9.526 |
| Sum of file spans, loading included | 5.053 | 4.106 |
| Loading sum | 3.904 | 3.986 |
| Visible test-body sum | 1.145 | 0.113 |

All three pairs favor the final candidate. Whole-process median decreases
**12.7%**, file-span sum **18.7%** and visible body sum **90.1%**. Child CPU
increases **0.6%**; a CPU improvement is not demonstrated for the final revision.
Each of the six timed commands passes the same nine cases, without skips.
Do not treat this focused result as a proven overall/CI improvement.

| Final full run, one sample/state | Before (s) | After (s) |
| --- | ---: | ---: |
| Whole process wall, launcher/hooks included | 208.261 | 208.672 |
| Child CPU | 1203.747 | 1218.229 |
| Sum of file spans, loading included | 1591.989 | 1593.255 |
| Loading sum | 681.147 | 662.237 |
| Visible test-body sum | 908.476 | 927.333 |

Both pass **1921 tests**, discover **268 entry-point files** and retain the exact
same **4 native-DLL skip names/reasons**. Full name/result/skip Counters match;
no baseline failure occurred. Whole-process wall grows **0.2%**, CPU **1.2%**;
**no overall speedup is demonstrated**. The changed file's full-run span drops
**4.224 -> 3.526s**, its bodies **1.205 -> 0.186s**. Untouched suites' file spans
grow by 1.964s, offset by this file's 0.698s reduction; one pair does not
establish why. Summed overlapping file spans are distinct from process elapsed
time. The supported speed claim remains the repeated focused result.

Validation:

- Both structural audits and all three deliberate fault comparisons above.
- `flutter analyze`: no issues, including type/lint/unused diagnostics.
  No separate unused-code check is configured for Dart.
- `dart format --output=none --set-exit-if-changed lib test integration_test`:
  800 files, zero changes.
- `python3 -B scripts/test-policy.py` and all seven example tests with
  `python3 -B -m unittest discover -s scripts -p test_test_policy.py`.
- All final source snapshots match the benchmarked/audited files after swaps.
  No runner lists, platform gates or CI defaults need changing.
- After the approved manifest declaration, `flutter test --machine
  test/features/voice_call/voice_call_orchestrator_test.dart
  --test-randomize-ordering-seed=42` passes all nine cases. Final analyze has
  no issues; format again checks 800 files without changes; policy passes.
- `git diff --check` passes; no unused timer/import/helper remains.

The approved dependency declaration makes the already locked/cached
`fake_async` **1.3.3** an explicit dev dependency (`^1.3.3`), without changing
its version. The user approved the two-line manifest/lock change required by
AGENTS.md. `flutter pub get --offline` changes only its classification in the
lockfile; all resolved versions/hashes remain exact. The final full command
ran with this same resolved 1.3.3 before the direct-dev classification; the
scoped randomized-order check and final analyze run after declaration.
The earlier `depend_on_referenced_packages` info is resolved by declaring the
dependency, with no lint suppression.

Limits: these are scripted capture/playback and bridge tests with actual local
frame crypto. They do not exercise native audio drivers, physical timing,
hardware or live transport. Those suites, production behavior, production dependencies,
bindings, public contracts, CI and runner configuration remain unchanged.
