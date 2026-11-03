# First-run flow and settings test cleanup

Baseline: `a7061a4b70dd179a178931493bc5df5d6a24103c`, initially clean.
Final source changes are limited to two test libraries: four assertion-preserving
MERGEs remove four repeated fixture starts. No DELETE decision or new case.

| Scope | Before | After | Retained protection |
| --- | ---: | ---: | --- |
| `first_run_flow_test.dart` | 26 | 24 | All 14 transition cases; network consent, failures, restart and both unmount races |
| `settings_screen_test.dart` | 7 | 5 | Real routes, every Back/Escape/pop/reopen path, direct entry, draft/scroll/search |
| Affected total | 33 | 29 | Every original assertion and distinct failure/lifetime boundary |
| Complete Flutter suite | 1862 + 4 native skips | 1858 + 4 native skips | Same 227 discovered runners |

## Final decisions and source proof

Network automatic completion joins the existing read-error→Retry flow after
its original fresh-form/no-consent assertions. Failed network reading never
built FirstRunNetworkForm or published routing state; successful Retry creates
the same automatic selection with no saved/live adapter or restart requirement.
The transferred Save-and-finish/zero-write/Sessions checks execute on that state.

Unsupported-restart modal checks join the existing failed-consent-save→Retry
flow. A refused setVpnBypassConsent did not publish saved adapter or completion.
On successful retry, assert dialog title, durable completed store and absent
Sessions **before Understood**, then actual Sessions afterward. Original error,
incomplete-store, retry and final completion assertions remain in order.

Settings wide sidebar checks execute before the first Back in the existing
gear/search/rail-identity case. After its original return assertions, actual
reopen→About→raw router.pop→reopen preserves selected About. The initial
null/default-sound observation stays before first exit; selecting About is
unconditional and does not depend on retained rail search or old provider value.

Settings narrow reopening joins system Back/Escape: Microphone before first
system Back; then real Back-to-chats→gear→list-reset assertions; then both original
Escape stages and final sessions route. Fresh reopened narrow state and former
post-Back list state both have showSection=false/selected sound. Regression
`255a4ef3` still fails if remembered section wrongly restores narrow detail.

Direct-root narrow toolbar-arrow, direct-root wide fallback and seeded40-message
DM draft/ScrollableState/exact-offset fixtures remain complete and unchanged.
Raw declarative pop (`4ee0ec2e`), system Back, arrow, Back-to-chats and Escape
are different event wiring, not interchangeable substitutes. Independent rail
mouse/touch ink-return and keyboard focus regressions remain and run in seed 42.

Source edits use Dart analyzer AST: exact file + full registration name, complete
statement removal and phase-specific assertion transfers. Immutable checks prove
all four source assertion sequences and retained target flows are ordered;
other complete test declarations, imports/helpers remain unchanged. Runtime
Counters verify file/full name/result/skip reason/multiplicity independently.
A green remaining suite alone is not assertion-preservation evidence.

No production/public API/schema/dependency, CI/discovery, global timeout/retry,
real wait, environment or Moss source change. No orphaned import/helper remains;
no new test abstraction is retained. Existing AGENTS/test-policy fixture/value
rules suffice. Existing guard rejects focus, requires reason/issue for new risky
forms and enforces scoped case ownership; seven examples pass unchanged.
Read root instructions, Architecture setup/settings, ADR 0036, testing/analysis/CI
configuration, implementation/support and available regression history before
editing. Root owns edits/measurements/commits; three reviewers work read-only
with distinct transition, network and settings ownership. Reviews establish
source evidence, not safety by vote count.

## Rejected experiments

The transition pilot kept all 14 callbacks, _go, providers/store/viewport/frame
schedule while adding optional appRoot to FirstRunHarness and a real Gate/Wizard
MaterialApp root. Default MoshApp was reconstructible exactly. Theme, locale,
NoSplash and ToastHost were retained, with one additional outer home Navigator.
A passive diagnostic copy ran the original 14 cases under both roots: all 14
initial geometry/profile/locale/theme/reduced-motion/fade/offset/blocking records
matched exactly. Normal/seed and original semantics/keyboard/retargeting tests
passed. Temporary probe files were removed; their runs are excluded from timing.

An initial pilot had a debug banner mismatch (17.619s/25.622CPU); it was corrected
before comparable sampling. Corrected transition-only fixture comparison, still
running the full 26-case command: original wall15.896/16.613s, CPU23.378/24.607s;
pilot wall15.511/15.447s, CPU22.899/22.450s. Local medians improved4.77%/5.49%.
This does not describe the later 24-case `flow-b1` (16.658s/24.286CPU), which also
contains network MERGEs. Keep these labels/states separate.

The combined candidate containing that root plus four MERGEs did not establish
a useful package gain: original wall15.669/19.389s, CPU33.970/42.476s; candidate
wall16.703/19.625s, CPU35.791/40.381s. Medians17.529→18.164s (+3.62%) and
38.223→38.086CPU (-0.36%). Those interleaved results do not isolate the root's
causal cost. The extra mode/Navigator/config duplication was unnecessary for
MERGEs, so it was rejected. **Both transition and support files are restored
byte-for-byte and mode-for-mode to Git baseline.** No such API is committed.

A third proposed network MERGE was also rejected. Assertions inside an
intentionally failing first restart callback can be caught as the expected
restart error; a later retry already sees completed storage and could mask an
ordering failure. Checking only before the throw is insufficient. Keep the
standalone Windows-success persist-before-start/executable/start→exit test and
restart-failure/retry case unchanged. No observation machinery was added just
to remove one fixture. Both consent-pending and completion-write-pending unmount
regressions (`8ab370de`) remain independent. Relevant histories include
`82f123bb`, `8901e9b1`, `eb9fa265`, `57179f34`, `6cd600ed`, `255a4ef3`,
`4ee0ec2e` and `0b040244`; known regressions are not deleted.

## Accepted scoped measurements

Same command: `flutter test --machine` with
`test/features/onboarding/first_run_flow_test.dart` and
`test/features/settings/settings_screen_test.dart`. Original33/final29 pass.
The freshest exact-baseline reverse control `scope-a2`, immediately preceding
the minimal candidate, is reused as accepted A1; after final B1/B2, seed and
static checks, `final-a2` is the reverse original control. Earlier experiment
samples above are retained separately, not silently pooled or discarded.

| Run | Complete command wall s | Child CPU s | File interval sum s | Loading sum s | Visible body sum s |
| --- | ---: | ---: | ---: | ---: | ---: |
| scope-a2 | 19.389 | 42.476 | 31.599 | 9.281 | 22.284 |
| final-b1 | 16.306 | 36.042 | 26.420 | 9.067 | 17.321 |
| final-b2 | 16.435 | 35.985 | 26.930 | 9.248 | 17.657 |
| final-a2 | 20.230 | 43.450 | 32.800 | 11.147 | 21.620 |

Accepted scope medians: wall **19.809 → 16.371 s** (-17.36%), CPU **42.963 → 36.014 s** (-16.18%).
Both forward and reverse controls favor the minimal candidate in wall and CPU; these remain
bounded observations on this shared host.

Final seed 42 adds unchanged first_run_entry 24 and rail settings ink/focus 4:
**57 passing cases**. Its different four-owner command is not pooled into timing
of the two affected owners. Original full-name Counters minus exactly four
MERGE source names match; no case is added or newly skipped. The module was
verified before settings expansion, and all final original transition callbacks
run through the restored real-app fixture.

## Complete-suite comparison

After final scoped/static checks, serial **A/B/B/A** runs execute exactly
`flutter test --machine` with ordinary configuration. Guarded snapshots restore
baseline test bytes/modes for A and exact final minimal source for B, refuse
unexpected edits, and restore final source afterward. Root starts no other
compiler/test/analyzer/formatter alongside timing. Other agents' host workload
and caches remain uncontrolled. Prior baseline-equivalent captures are context,
not pooled with these fresh full measurements.

| Run | Complete command wall s | Child CPU s | File interval sum s | Loading sum s | Visible body sum s |
| --- | ---: | ---: | ---: | ---: | ---: |
| whole-a1 | 140.377 | 1109.352 | 1063.390 | 447.138 | 614.237 |
| whole-b1 | 143.635 | 1174.691 | 1094.232 | 457.122 | 635.333 |
| whole-b2 | 133.796 | 1089.145 | 1017.515 | 426.277 | 589.761 |
| whole-a2 | 140.990 | 1162.453 | 1075.122 | 442.132 | 631.196 |

Complete-series medians: wall **140.684 → 138.715 s** (-1.40%), CPU **1135.903 → 1131.918 s**
(-0.35%). File interval sums 1069.256 → 1055.873 s. With 2 samples/state, median equals mean.
Forward and reverse comparisons do not both favor the candidate. A stable whole-suite speedup is
NOT established; the median difference is an observation under shared-host variation, not a causal
guarantee. Unchanged original wall spread is 0.614s; identical candidate runs differ by 9.838s,
compared with a 1.968s difference between medians. All samples are included.

Complete wall includes launcher/hooks. CPU is completed child/descendant user+
system time (RUSAGE_CHILDREN). File intervals span each runner's first start
through final completion; loading is the hidden loader, bodies visible non-skipped
cases. Those intervals overlap across parallel workers: their sums are neither
elapsed nor exclusive CPU. A lower first-test duration can move initialization
rather than eliminate work. No CI/cold-build/hardware/native speed guarantee.

## Verification and limits

- Exact four-source Counter reduction, retained assertion/phase/source proof,
  normal scopes and seed 42 pass. No failure is classified as pre-existing;
  no baseline-failure worktree reproduction is needed.
- Full runs retain same 227 runners and four native gates, A1862/B1858 passes.
- `flutter analyze`: no issues (9.2s), including unused-import/element/dead-code
  checks. No separate unused-code tool is configured.
- `dart format --output=none --set-exit-if-changed lib test integration_test`:
  816 files, zero changes. Existing policy and seven executable examples pass.
- All changed test files stay below400 lines; complete main declaration blocks
  retain the existing size exception. No production/API/binding change or new
  helper abstraction, timeout/retry/sleep/skip exception, linter or test lane.
- Native/device/OS/Rust/integration and optional preview/font/screenshot modes
  were not run; their sources/gates remain unchanged. Seed42 is not all orders.
  No mutation/coverage-percentage result is claimed for unchanged production.
- MERGE failures have broader phase sequences; every original phase is asserted,
  but removed registrations are no longer individually selectable by name.

The same four skips are in `test/gateway/real_bridge_dispatch_test.dart`, reason
`native libs not built: mosh-core/target/release/mosh_core.dll / moss-runtime/moss.dll`:

- `channel: send lands in the channel runtime`
- `dm: send lands in the DM runtime; a missing id answers typed`
- `group: send lands in the group runtime; after leave the lookup misses`
- `undecodable attachment bytes cross as the typed error on every kind`
 Actual native initialization/protocol probes
keep their worker boundaries and original conditions.

## Exact original case ledger

Each row combines the source file and complete original runtime describe/test
path. Network/transition groups execute through `first_run_flow_test.dart`;
settings names are ungrouped. All retained registration names are unchanged.

| Source + complete runtime path | Protected contract | Decision | Evidence / retained replacement |
| --- | --- | --- | --- |
| `test/features/onboarding/first_run_network_cases.dart` / `first_run_network Back and Continue keep the unsaved adapter selection` | Visited network form preserves uncommitted selection without reload | KEEP | Actual Back/Continue, warning, zero-consent and one-interface-read checks unchanged; not replaced by provider persistence tests. |
| `test/features/onboarding/first_run_network_cases.dart` / `first_run_network Windows saves completion before starting the replacement` | Persist-before-start, executable and start→exit ordering | KEEP | Complete callback remains byte-identical. Merge into expected restart failure rejected: production catch can swallow a starter assertion, and later retry already sees persisted completion. |
| `test/features/onboarding/first_run_network_cases.dart` / `first_run_network automatic routing never writes bypass consent or relaunches` | Automatic finish reaches chats without bypass consent | MERGE | All finish/zero-write/Sessions assertions retained after the recovered automatic form in first_run_network network read failure recovers without changing consent. |
| `test/features/onboarding/first_run_network_cases.dart` / `first_run_network closing during completion save still completes and restarts` | Unmount while profile completion write is pending still restarts | KEEP | Separate 8ab370de storage boundary; its held store future and all assertions remain unchanged. |
| `test/features/onboarding/first_run_network_cases.dart` / `first_run_network closing during consent save still completes and restarts` | Unmount while native consent is pending still finishes durably | KEEP | 8ab370de regression, real held bridge operation released only after unmount; post-completion/start ordering unchanged. |
| `test/features/onboarding/first_run_network_cases.dart` / `first_run_network detected VPN is explained without silently enabling bypass` | Detected default-route VPN gets truthful warning and no implicit consent | KEEP | Security/consent branch stays distinct from plain automatic routing; all UI and bridge assertions unchanged. |
| `test/features/onboarding/first_run_network_cases.dart` / `first_run_network failed bypass write keeps setup open and can retry` | Refused consent save stays incomplete; retry persists and explains restart | MERGE target | Original failure/retry statements remain; transferred manual-restart title/store.completed/no-Sessions checks run before Understood, Sessions afterward. Failed write did not publish adapter/completion state. |
| `test/features/onboarding/first_run_network_cases.dart` / `first_run_network network read failure recovers without changing consent` | Read error → Retry → automatic form → no-consent completion | MERGE target | Original error/retry/no-write checks precede transferred Save and finish + zero-write + actual SessionsScreen. The failed read never built a form; Retry creates the same fresh automatic state. |
| `test/features/onboarding/first_run_network_cases.dart` / `first_run_network resizing preserves the selected adapter and bypass explanation` | Selected adapter/warning survive small viewport and later save | KEEP | 320×568 and 1280×680 geometry, actual save/consent/Understood and optional preview unchanged. |
| `test/features/onboarding/first_run_network_cases.dart` / `first_run_network restart failure retains the saved choice and enables retry` | Restart failure keeps completed record and working retry | KEEP | Distinct expected-error and later successful-start path; unchanged source, no assertion moved into its caught failing callback. |
| `test/features/onboarding/first_run_network_cases.dart` / `first_run_network unavailable saved adapter must be replaced before finishing` | Missing persisted adapter blocks completion until deliberate replacement | KEEP | External/runtime availability and disabled control remain, including explicit clearing to automatic routing. |
| `test/features/onboarding/first_run_network_cases.dart` / `first_run_network unsupported relaunch explains manual restart before chats` | Unsupported restart commits completion but gates chats behind dialog | MERGE | All four modal/completion/no-Sessions/after-Understood assertions retained in first_run_network failed bypass write keeps setup open and can retry, at the same pre/post-dialog phases. |
| `test/features/onboarding/first_run_transition_cases.dart` / `first_run_transition Back reverses the subtle slide and restores the saved name` | Actual Back reverses direction and restores typed stored name | KEEP | Whole source file and shared harness equal baseline after rejected fixture pilot; all providers, frame durations, actions/assertions stay. History eb9fa265/57179f34/8901e9b1; no blanket timing or library-only deletion. |
| `test/features/onboarding/first_run_transition_cases.dart` / `first_run_transition Continue crossfades the content without a blank interval` | Real save/Continue, simultaneous outgoing/incoming opacity and forward direction | KEEP | Whole source file and shared harness equal baseline after rejected fixture pilot; all providers, frame durations, actions/assertions stay. History eb9fa265/57179f34/8901e9b1; no blanket timing or library-only deletion. |
| `test/features/onboarding/first_run_transition_cases.dart` / `first_run_transition SetupStep.device restores without an entrance animation` | Cold restored step has full opacity/zero offset and usable controls | KEEP | Independent initial step, initial frame plus40ms checks; original full Gate/harness and every body restored byte-for-byte.8901e9b1. |
| `test/features/onboarding/first_run_transition_cases.dart` / `first_run_transition SetupStep.name restores without an entrance animation` | Cold restored step has full opacity/zero offset and usable controls | KEEP | Independent initial step, initial frame plus40ms checks; original full Gate/harness and every body restored byte-for-byte.8901e9b1. |
| `test/features/onboarding/first_run_transition_cases.dart` / `first_run_transition SetupStep.network restores without an entrance animation` | Cold restored step has full opacity/zero offset and usable controls | KEEP | Independent initial step, initial frame plus40ms checks; original full Gate/harness and every body restored byte-for-byte.8901e9b1. |
| `test/features/onboarding/first_run_transition_cases.dart` / `first_run_transition a return during exit retargets without remounting the form` | Interrupted transition retains exact form state/text/position | KEEP | Whole source file and shared harness equal baseline after rejected fixture pilot; all providers, frame durations, actions/assertions stay. History eb9fa265/57179f34/8901e9b1; no blanket timing or library-only deletion. |
| `test/features/onboarding/first_run_transition_cases.dart` / `first_run_transition advancing on a phone keeps outgoing card geometry stable` | Phone card size survives outgoing/active overlap | KEEP | Whole source file and shared harness equal baseline after rejected fixture pilot; all providers, frame durations, actions/assertions stay. History eb9fa265/57179f34/8901e9b1; no blanket timing or library-only deletion. |
| `test/features/onboarding/first_run_transition_cases.dart` / `first_run_transition enabling reduce motion during a transition removes the slide` | Dynamic accessibility preference changes translation without opacity jump | KEEP | Whole source file and shared harness equal baseline after rejected fixture pilot; all providers, frame durations, actions/assertions stay. History eb9fa265/57179f34/8901e9b1; no blanket timing or library-only deletion. |
| `test/features/onboarding/first_run_transition_cases.dart` / `first_run_transition outgoing Back cannot change the active step` | Outgoing pointer input cannot mutate active profile step | KEEP | Whole source file and shared harness equal baseline after rejected fixture pilot; all providers, frame durations, actions/assertions stay. History eb9fa265/57179f34/8901e9b1; no blanket timing or library-only deletion. |
| `test/features/onboarding/first_run_transition_cases.dart` / `first_run_transition outgoing controls leave semantics and keyboard traversal` | Inactive controls stop screen-reader and keyboard participation | KEEP | Whole source file and shared harness equal baseline after rejected fixture pilot; all providers, frame durations, actions/assertions stay. History eb9fa265/57179f34/8901e9b1; no blanket timing or library-only deletion. |
| `test/features/onboarding/first_run_transition_cases.dart` / `first_run_transition rapid requests reveal only the latest step` | Multiple in-flight requests keep newest panel and continuous retargeting | KEEP | Whole source file and shared harness equal baseline after rejected fixture pilot; all providers, frame durations, actions/assertions stay. History eb9fa265/57179f34/8901e9b1; no blanket timing or library-only deletion. |
| `test/features/onboarding/first_run_transition_cases.dart` / `first_run_transition reduced motion allows Back on the next frame without translation` | Reduced motion removes translation and permits Back on next frame | KEEP | Whole source file and shared harness equal baseline after rejected fixture pilot; all providers, frame durations, actions/assertions stay. History eb9fa265/57179f34/8901e9b1; no blanket timing or library-only deletion. |
| `test/features/onboarding/first_run_transition_cases.dart` / `first_run_transition same-step edits, resizing and failed saves do not replay motion` | Same-step data/viewport/save failure preserve draft and settled animation | KEEP | Whole source file and shared harness equal baseline after rejected fixture pilot; all providers, frame durations, actions/assertions stay. History eb9fa265/57179f34/8901e9b1; no blanket timing or library-only deletion. |
| `test/features/onboarding/first_run_transition_cases.dart` / `first_run_transition unmounting during motion disposes its ticker` | Animation ticker disposal on actual widget unmount | KEEP | Whole source file and shared harness equal baseline after rejected fixture pilot; all providers, frame durations, actions/assertions stay. History eb9fa265/57179f34/8901e9b1; no blanket timing or library-only deletion. |
| `test/features/settings/settings_screen_test.dart` / `closing settings restores the open chat, scroll and draft` | Actual DM route, draft, ScrollableState identity and exact offset survive overlay | KEEP | Complete seeded40-message fixture, real router, body/actions/assertions unchanged; empty rail does not replace open-chat state. |
| `test/features/settings/settings_screen_test.dart` / `direct settings entry can return to the chat list` | Direct wide root has no route to pop; Back falls back to sessions | KEEP | Complete direct-root fallback case unchanged, preserving canPop=false→go branch and null/default section initialization. |
| `test/features/settings/settings_screen_test.dart` / `gear opens standalone settings and returns to preserved chats` | Standalone wide route preserves same rail/search and remembers selected section | MERGE target | Original gear/Back/identity/search sequence retained. Sidebar assertions precede first Back; actual reopen→About→raw router.pop→reopen tail follows original return checks. |
| `test/features/settings/settings_screen_test.dart` / `narrow sections open as details and Back returns to the list` | Direct-root narrow list/detail with toolbar-arrow return | KEEP | Complete direct-root fixture unchanged; overlay pop and Escape cannot replace its initial route/arrow wiring. |
| `test/features/settings/settings_screen_test.dart` / `reopening narrow settings starts at the section list` | Fresh narrow route starts at list despite remembered section | MERGE | Full first-detail/system-Back/Back-to-chats/gear/new-list lifecycle retained in system Back and Escape unwind narrow detail before settings.255a4ef3 remains sensitive to incorrectly restored _showSection. |
| `test/features/settings/settings_screen_test.dart` / `system Back and Escape unwind narrow detail before settings` | Pushed narrow route consumes Back/Escape, reopens list and then exits to chats | MERGE target | Microphone check before first system Back; actual Back-to-chats/gear/list-reset assertions before both original Escape stages and final sessions checks. |
| `test/features/settings/settings_screen_test.dart` / `wide sidebar switches sections and remembers on reopening` | Wide default sidebar and About survive actual route disposal/reopen | MERGE | All assertions and About/pop/reopen lifecycle move into gear opens standalone settings and returns to preserved chats. Initial null/default observation remains before first exit; _select(About) ignores old provider value.4ee0ec2e deferred-pop regression retained. |

## Changed files

`test/features/onboarding/first_run_network_cases.dart`,
`test/features/settings/settings_screen_test.dart`, `docs/testing.md`, and this
report. No physical file deletion; all four removed registrations are MERGE,
not lost contracts. Historical audits retain their original names/results.
Private raw JSONL, commands/CPU/wall records, source snapshots, AST/probe tools
and independent reviews reside in `.git/test-audit/flow-settings-next/` and are
not required by CI. Local Conventional Commit only; no push, deploy, publication
or tracker write.
