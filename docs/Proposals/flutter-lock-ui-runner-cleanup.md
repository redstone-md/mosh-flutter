# Bounded startup-lock UI runner

Baseline: `b784dafec7148bb35cdd8d8d3a1058c0f6994ae2`, initially clean.
Three startup-lock UI libraries share one synchronous entry point. All fourteen
scenarios, assertions, helpers, injected callbacks and clock steps remain.
Sibling case files preserve the original source bytes and modes exactly.
There are no DELETE, MERGE, fixture or timing rewrites.

| Scope | Before | After |
| --- | ---: | ---: |
| Selected UI cases / runners | 14 / 3 | 14 / 1 |
| Entire lock folder cases / runners | 29 / 7 | 29 / 5 |
| Complete Flutter passes / native skips / runners | 1858 / 4 / 224 | 1858 / 4 / 222 |

## Contract and isolation evidence

Read AGENTS, Architecture, ADR 0011, test/analysis/CI configuration, all three
libraries, MoshLockScreen/MoshLockApp, native-DEK/locale seams and existing pump
helpers. Available regression history includes `0e2be3e0`, `b1df0ca7`, `b743f14a`,
`7242895a` and `c238d04b`. No authentication, error-code, language or fail-closed
scenario is deleted. Root owns edits, measurements and commits; an independent
read-only reviewer checks source/history, immutable copies, isolation and logs.

`lock_ui_test.dart` only imports three sibling case libraries under namespaces
and registers `group('stem', module.main)`. The existing policy requires exactly
one scoped owner per case library. Exact Git byte/mode copies establish retained
callback/action/assertion/fixture preservation independently of green runs.
Outcome Counters independently match file, full name, result, skipped flag,
reason and multiplicity after stripping only these three new group prefixes
and mapping the new runtime owner to each original test file.

Every selected screen injects its retry callback and a SizedBox next-app target.
No real initMobileDek, Keystore, FRB, channel or HTTP request is reached by these
UI traces; a real unlocked MoshApp is not mounted. The successful retry still
holds its Completer while asserting spinner and no early swap, completes it,
then uses the original plain pumps and exactly-one-target-swap assertions.
It does not settle an indefinitely animated success spinner. Widget teardown
remains per test. Error cases retain all nine external platform codes and
zero-swap assertions, including unavailable credentials with no Retry button.

The locale case retains real MoshLockApp/LocaleNotifier and its local Russian
MemoryLocalePreferenceStore override; no OS/global locale override or disk
preference mutation is introduced. The other cases keep their original
localized MaterialApp fixtures. No new shared fixture is introduced.

Four original `pumpAndSettle(Duration(seconds: 5))` calls stay byte-identical.
They advance the widget fake clock; they are not five-second real sleeps or
local timeout increases. This patch does not claim to remove twenty seconds
of elapsed waiting. Existing guard examples distinguish retry callbacks from
test retry budgets; the three moved libraries have no risky policy expressions.

The four Android app-access/authentication/resume/app-lock owners stay separate,
retaining their method-channel handlers, cleanup, lifecycle and observer state.
Folder/full commands still run them. The one affected documentation test list
now names `lock_language_cases.dart` and `lock_ui_test.dart`; no executable
consumer or CI path list needs changing. CI still discovers ordinary test owners.

## Exact retained case ledger

All rows are KEEP. Only sibling source paths, the runtime owner and source-stem group prefixes change.
New runtime owner for every row: `test/features/lock/lock_ui_test.dart`.

| Original file / full test path | Protected contract | Decision / new full group/test path |
| --- | --- | --- |
| `test/features/lock/lock_language_test.dart` / `the startup lock screen uses the saved interface language` | Real startup lock app reads saved Russian locale, renders localized title and has no framework exception. | KEEP; `lock_language the startup lock screen uses the saved interface language`. Complete source bytes/mode unchanged. |
| `test/features/lock/mosh_lock_screen_errors_test.dart` / `retry classifies AUTHENTICATION_CANCELED without exposing chats` | Native cancellation spelling retains canceled UI and zero root swaps. | KEEP; `mosh_lock_screen_errors retry classifies AUTHENTICATION_CANCELED without exposing chats`. Complete source bytes/mode unchanged. |
| `test/features/lock/mosh_lock_screen_errors_test.dart` / `retry classifies AUTHENTICATION_CANCELLED without exposing chats` | Alternate native cancellation spelling retains canceled UI and zero root swaps. | KEEP; `mosh_lock_screen_errors retry classifies AUTHENTICATION_CANCELLED without exposing chats`. Complete source bytes/mode unchanged. |
| `test/features/lock/mosh_lock_screen_errors_test.dart` / `retry classifies BIOMETRIC_UNAVAILABLE without exposing chats` | Unavailable credentials show unsecured-device UI, no Retry and zero root swaps. | KEEP; `mosh_lock_screen_errors retry classifies BIOMETRIC_UNAVAILABLE without exposing chats`. Complete source bytes/mode unchanged. |
| `test/features/lock/mosh_lock_screen_errors_test.dart` / `retry classifies DEK_ENVELOPE_INVALID without exposing chats` | Invalid key envelope shows failure and zero root swaps. | KEEP; `mosh_lock_screen_errors retry classifies DEK_ENVELOPE_INVALID without exposing chats`. Complete source bytes/mode unchanged. |
| `test/features/lock/mosh_lock_screen_errors_test.dart` / `retry classifies DEK_STORAGE_UNAVAILABLE without exposing chats` | Unavailable encrypted-key storage shows failure and zero root swaps. | KEEP; `mosh_lock_screen_errors retry classifies DEK_STORAGE_UNAVAILABLE without exposing chats`. Complete source bytes/mode unchanged. |
| `test/features/lock/mosh_lock_screen_errors_test.dart` / `retry classifies UNKNOWN_FAILURE without exposing chats` | Unknown platform failure remains locked with zero root swaps. | KEEP; `mosh_lock_screen_errors retry classifies UNKNOWN_FAILURE without exposing chats`. Complete source bytes/mode unchanged. |
| `test/features/lock/mosh_lock_screen_errors_test.dart` / `retry classifies cancel without exposing chats` | Legacy cancel spelling retains canceled UI and zero root swaps. | KEEP; `mosh_lock_screen_errors retry classifies cancel without exposing chats`. Complete source bytes/mode unchanged. |
| `test/features/lock/mosh_lock_screen_errors_test.dart` / `retry classifies canceled without exposing chats` | Legacy canceled spelling retains canceled UI and zero root swaps. | KEEP; `mosh_lock_screen_errors retry classifies canceled without exposing chats`. Complete source bytes/mode unchanged. |
| `test/features/lock/mosh_lock_screen_errors_test.dart` / `retry classifies cancelled without exposing chats` | Legacy cancelled spelling retains canceled UI and zero root swaps. | KEEP; `mosh_lock_screen_errors retry classifies cancelled without exposing chats`. Complete source bytes/mode unchanged. |
| `test/features/lock/mosh_lock_screen_test.dart` / `a second biometric cancel stays on the lock screen` | Retry cancellation restores Retry/no-spinner, calls the fake once and never swaps to chats. | KEEP; `mosh_lock_screen a second biometric cancel stays on the lock screen`. Complete source bytes/mode unchanged. |
| `test/features/lock/mosh_lock_screen_test.dart` / `canceled state shows title, message, and Retry button` | Canceled startup shows lock title/explanation/Retry and no spinner. | KEEP; `mosh_lock_screen canceled state shows title, message, and Retry button`. Complete source bytes/mode unchanged. |
| `test/features/lock/mosh_lock_screen_test.dart` / `insecureDevice state shows title + message, no Retry button` | Unsecured device explains required credentials and offers neither Retry nor spinner. | KEEP; `mosh_lock_screen insecureDevice state shows title + message, no Retry button`. Complete source bytes/mode unchanged. |
| `test/features/lock/mosh_lock_screen_test.dart` / `tap Retry transitions to authenticating then swaps to nextApp` | Held authentication shows spinner and no early root swap; completion swaps exactly once to the original target. | KEEP; `mosh_lock_screen tap Retry transitions to authenticating then swaps to nextApp`. Complete source bytes/mode unchanged. |

## Scoped comparison

Initial validation of the three original file arguments passes all fourteen:
9.248 s complete wall, 19.388 s child CPU. The new single driver passes the exact
normalized fourteen in 8.061 s wall / 11.972 s CPU. These argv differ and are
validation captures, not the formal performance comparison.

Formal command in both states: `flutter test --machine test/features/lock`.
Three serial pairs use A/B, B/A, A/B. Every run passes the same 29 cases. Guarded
snapshots restore only the seven owned test paths, refuse unexpected source
states, and restore the final candidate afterward. No sample is discarded.

| Run | Complete wall s | Child CPU s | File sum s | Loading sum s | Visible body sum s |
| --- | ---: | ---: | ---: | ---: | ---: |
| lock-a1 | 10.894 | 29.836 | 51.542 | 42.667 | 8.854 |
| lock-b1 | 9.260 | 23.288 | 31.848 | 24.488 | 7.329 |
| lock-b2 | 9.333 | 23.200 | 32.101 | 25.524 | 6.550 |
| lock-a2 | 9.782 | 26.706 | 45.277 | 37.011 | 8.249 |
| lock-a3 | 10.428 | 28.198 | 48.217 | 39.227 | 8.970 |
| lock-b3 | 9.461 | 23.874 | 33.066 | 25.995 | 7.045 |

Folder medians: wall **10.428 → 9.333 s** (-10.50%), CPU **28.198 → 23.288 s** (-17.41%).
Wall favors the candidate in 3/3 pairs. CPU favors the candidate in 3/3 pairs.

The candidate folder also passes seed 42 with the exact same normalized 29-case
Counter. Timed commands use ordinary warm caches and unchanged settings. Root
starts no test/compiler/analyzer/formatter alongside timing. Other agents use
the server; observed module savings are not a CI/hardware guarantee.

## Complete-suite comparison

After module/static checks, four serial ordinary `flutter test --machine`
commands use A/B/B/A, with exact original or candidate bytes/modes. A guard also
refuses unrelated tracked/untracked edits and HEAD changes. Dependencies,
production, CI, concurrency, platform gates and global timing defaults stay
unchanged. All command results and normalized complete Counters are checked.

| Run | Complete wall s | Child CPU s | File sum s | Loading sum s | Visible body sum s |
| --- | ---: | ---: | ---: | ---: | ---: |
| whole-a1 | 141.756 | 1172.474 | 1080.924 | 436.416 | 642.761 |
| whole-b1 | 143.683 | 1190.033 | 1095.218 | 445.113 | 648.249 |
| whole-b2 | 147.795 | 1231.686 | 1125.009 | 450.977 | 671.996 |
| whole-a2 | 159.990 | 1308.359 | 1218.571 | 514.226 | 702.435 |

Full medians: wall **150.873 → 145.739 s** (-3.40%), CPU **1240.417 → 1210.859 s** (-2.38%).
File sum medians: 1149.7475 → 1110.1135 s.
With two samples/state, median equals mean. Forward and reverse controls do not both favor the candidate for wall and CPU.
A consistent whole-suite speedup is **not established**; a smaller median, if any,
is a shared-host observation rather than a causal guarantee.
Original same-source wall spread is 18.234 s; candidate spread is 4.112 s,
against a 5.134 s median difference. All samples remain in the comparison.
The batch is retained for the three-pair module saving and two fewer startup
owners; its complete-suite/CI speedup is not claimed as established.
All four full Counters match after the exact owner/prefix mapping: 1858 passes,
the same four native skips, 224 original / 222 final runners. No case or assertion is removed.

Selected owner file-span medians: 9.9285 → 4.2550 s; the other 221 unchanged owners: 1139.8190 → 1105.8585 s.
These overlapping intervals are not per-owner CPU or critical-path wall.
Untouched-owner changes are not isolated from scheduling, cache and shared-host
effects. Do not present the entire elapsed difference as guaranteed seconds
directly saved by two fewer runners.

Wall is the complete command including launcher/native hooks. CPU is completed
descendant user+system time (RUSAGE_CHILDREN). File spans cover loading through
final completion; loading and visible non-skipped test intervals are reported
separately. Intervals overlap across workers and are neither elapsed nor
exclusive CPU. Independently calculated medians need not add. Warmup can move
between hidden loading and the first test without disappearing. No cold-build,
physical-device or universal performance claim is made.

## Verification and limits

- Three case files match original Git bytes/modes, every case library has exactly
  one scoped owner, and the only new Dart logic is a 12-line registration driver.
  No import, helper, fixture, assertion, frame or starting state is lost.
- Original/pilot 14-case Counters, six 29-case folder captures, seed 42 and four
  full captures pass exact normalized identity/result/skip/reason comparisons.
- `flutter analyze`: no issues (10.0 s), including type/lint and unused import,
  element/dead-code diagnostics; no separate unused-code tool is configured.
- `dart format --output=none --set-exit-if-changed lib test integration_test`:
  818 files, zero changes. Policy, seven policy examples and diff checks pass.
- Case files are 190/38/33 lines; the driver is 12. Existing long test declaration
  blocks/scenarios are copied unchanged; no new long function/type is introduced.
- No failure is classified as pre-existing and no baseline-failure worktree is
  needed. No new coverage percentage or executed mutation result is claimed.

Existing lint/policy coverage is sufficient; AGENTS already requires valuable
contracts, scoped ownership and policy checks. No new focus, skip, todo, timeout,
retry budget, real delay, rule, dependency, test abstraction or exception is added.
No production, schema, public API, generated binding or Moss source is modified.

Risks: fourteen cases now share one worker. Future global state/handler changes
must retain compatible cleanup; seed 42 does not prove every possible ordering.
Full names gain documented prefixes. Debug through the new driver, or explicitly
run one sibling case library. Native/device/real-keystore/Rust integration is
unchanged and unrun; UI fakes do not demonstrate real biometric/key-storage safety.

Four skips remain in `test/gateway/real_bridge_dispatch_test.dart`:

- `undecodable attachment bytes cross as the typed error on every kind`
- `dm: send lands in the DM runtime; a missing id answers typed`
- `channel: send lands in the channel runtime`
- `group: send lands in the group runtime; after leave the lookup misses`

Their unchanged reason is `native libs not built: mosh-core/target/release/mosh_core.dll / moss-runtime/moss.dll`.
The conditional media-kit thumbnail probe passes; it is not another skip.

## Changed files

- Exact sibling renames under `test/features/lock/`: `mosh_lock_screen`,
  `mosh_lock_screen_errors`, `lock_language`, each from `*_test.dart` to `*_cases.dart`.
- New `test/features/lock/lock_ui_test.dart` (12 lines).
- This audit, its `docs/testing.md` pointer and the affected test/support list
  in `docs/Proposals/issues-45-48.plan.md`.

Raw sources, command logs, measurements, Counter/preservation proofs and the
independent review stay private under `.git/test-audit/lock-ui-next/`.
No build artifact is committed; nothing is pushed, deployed or published.
