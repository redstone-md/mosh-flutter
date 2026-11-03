# Auto-poll clock experiments: rejected

Baseline: `c03db25b8c82a02b994c7a17a1d858e893309449` on
`test/prune-low-value-suites`; clean tree before investigation.
All test/helper changes are restored to the baseline. Only this audit and a
measurement-policy note remain. No acceleration is claimed.

## Contract ledger

Read `autoPollProvider`, `ForegroundPoller`, `ConversationListNotifier`, the
scripted bridge/gateway, Architecture and Android background ADR 0048. Read
the `e6d61fcc` snapshot-after-list regression diff and lifecycle history from
`5af912cb` / `c238d04b`. These are UI refresh/backpressure regressions; native
background reception has separate tests.

Four ordinary tests contain six real waits totalling 350ms. No safe DELETE or
MERGE was established. All paths below belong to
`test/state/auto_poll_provider_test.dart`, without a describe prefix.

| Full test path | Protected contract | Final decision |
| --- | --- | --- |
| `an Android UI mounted detached waits for resume before polling` | Detached reads stay stopped; resume refreshes once; inactive visible prompts keep polling. | KEEP exact original. |
| `Android stops UI reads while paused and refreshes on resume` | Hidden Android stops reads; return refreshes immediately. | KEEP exact original. |
| `a foreground return keeps one outstanding read per kind` | Resume neither duplicates a held DM read nor blocks other kinds. | KEEP exact original. |
| `desktop UI continues polling when its window is hidden` | Desktop retains polling while hidden. | KEEP including platform override/reset. |
| `an Android UI mounted while paused waits for foreground` | Paused initial mount queues no reads, then resume refreshes. | KEEP exact original. |
| `the auto-poll loop re-queries the bridge with no mutation` | Every kind refreshes without a user mutation. | KEEP; reject the clock rewrite because complete-run cost did not improve. |
| `a stuck kind does not hold the other kinds back` | One DM read stays held while channels continue refreshing. | KEEP original exact/lower-bound counts and hold/release. |
| `the open conversation re-reads after its list, not behind a stuck one` | Snapshot follows completed lists and does not queue behind a held list (`e6d61fcc`). | KEEP this concurrency regression, shared seed, subscription and both assertions. |
| `no interval bound -> no polling (the flutter test default)` | Null default starts no polling. | KEEP; evaluate stronger virtual window, but reject its surrounding optimization. |

## Variants and preservation evidence

1. Convert four cases to the existing `testWidgets` clock. All nine pass, but
   the installed automated binding supplies a 10-minute default instead of the
   ordinary test's 30 seconds. Reject this implicit deadline increase rather
   than adding local overrides. Scope result: 9.416s wall / 12.744s child CPU.
2. Keep ordinary registrations and extract the existing async fake-clock helper
   unchanged from the voice suite into `test/support/clock.dart`. Seven voice
   plus four auto-poll callers share it. A literal-window prototype passes all
   nine (11.299s wall / 13.549s CPU). Replace margins with required ticks: two
   recurring, three held-kind, two/one/three snapshot phases, two production
   periods for null interval. Three-pair medians grow **8.853 -> 9.205s wall
   (+4.0%)**, **11.801 -> 12.238s CPU (+3.7%)**, although bodies shrink
   1.059 -> 0.721s. Reject; restore both voice files exactly and remove the new
   shared helper.
3. Use `fakeAsync` directly with no new helper or voice changes. Four prefetch
   sites become a provider read, zero-time drain and explicit `hasValue` check,
   so setup must actually resolve before counting polls. Preserve all original
   assertions, the configured 10ms cadence and ordinary deadlines; use required
   tick phases and check timer cleanup. The final comparison below still does
   not establish a cheaper complete runner. Restore this variant too.

AST edits address exact file/name identities. Audits reconstruct every original
assertion, fixture input, configured interval, hold/release, subscription and
global setup after removing only clock/readiness preparation. Five lifecycle
cases stay exact. The proposed voice helper move is separately compared
byte/token-for-token. Green remaining tests are not the sole preservation proof.

Diagnostic copies in `.git/test-audit/auto-poll/` show the async-clock variant
catches the intended failures, without mutating production:

- Add snapshot invalidation on each tick before its list finishes: the snapshot
  regression fails its held-list negative assertion.
- Remove the pending-read guard: the stuck-kind case rejects multiple DM reads.
- Substitute the 1s production cadence for null interval: the original 60ms
  case passes; two production periods reject the extra reads. This is a useful
  coverage gap for a separate targeted change.

Every source swap checks/restores bytes in `finally`. An AST constructor-shape
error and a copied guard's compilation error are recorded separately; neither
is accepted as fault evidence or a baseline failure. Useful failing tests are
never removed or hidden. No test is added to confirm another test's deletion.

## Final direct-clock measurements

Identical command for each source state:

```sh
flutter test --machine test/state/auto_poll_provider_test.dart
```

Serial commands, ordinary warm caches, unchanged settings and dependencies.
No own analyzer/compiler or other test command overlaps timed invocations.

| Pair | Before process wall (s) | Candidate process wall (s) | Order |
| --- | ---: | ---: | --- |
| 1 | 8.764 | 8.573 | A/B |
| 2 | 8.587 | 8.106 | B/A |
| 3 | 8.245 | 8.590 | A/B |

| Median, 3 samples/state | Before (s) | Candidate (s) |
| --- | ---: | ---: |
| Whole process wall, launcher/hooks included | 8.587 | 8.573 |
| Child CPU | 11.870 | 12.279 |
| Sum of file spans, loading included | 6.044 | 5.882 |
| Loading sum | 4.942 | 5.161 |
| Visible test-body sum | 0.973 | 0.686 |

Bodies decrease **29.5%**, but process wall only **0.2%**, with one pair slower;
CPU increases **3.4%**. Removing 350ms of sleeps does not establish 350ms of
process-wall savings. Do not retain extra clock/setup machinery as a runtime
optimization on this evidence. Timing variation's cause is not established;
no environment tuning is attempted.

The unchanged full baseline (`flutter test --machine`) passes **1921 tests**,
with **4 native-DLL skips**, **268 entry-point files**, zero failures:
**213.883s process wall**, **1266.239s child CPU**, **1639.769s summed file spans**
(694.015s loading, 942.846s visible bodies). File sums overlap and are not elapsed
execution time. There is no candidate full-run speed claim. After all test
sources are restored, another full run is unnecessary for this docs-only result.

## Final verification and limits

- All test, helper, production, native/integration and dependency diffs against
  the baseline are empty. The auto-poll file matches its immutable bytes; both
  voice files match exactly and the experimental shared helper is absent.
- Final `flutter test --machine test/state/auto_poll_provider_test.dart` passes
  all nine original full names without skips; its outcome Counter matches the
  first baseline exactly. Final restoration check: 9.159s wall / 12.454s CPU,
  outside the predefined comparison cohort.
- `flutter analyze`: no issues, including configured type/lint/unused checks.
  No separate Dart unused-code checker is configured.
- `dart format --output=none --set-exit-if-changed lib test integration_test`:
  800 files, zero changes. `python3 -B scripts/test-policy.py` passes.
- `git diff --check` passes. Only this report and the measurement-policy note
  change; there are no runner-list or CI updates to make.

Artifacts, raw commands/outcomes/timings, rejected sources, immutable baseline
and swap/audit scripts remain local in `.git/test-audit/auto-poll/`. The six
legacy waits remain debt. Native/live runners are not run. Their gates,
production behavior, dependencies, public contracts and CI stay unchanged.
