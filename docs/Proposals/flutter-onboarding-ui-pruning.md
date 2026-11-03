# Onboarding UI test pruning

Baseline: `0af027f30b40afe62fb5193147423c9460700233`, initially clean.
This round removes repeated UI setup and redundant shared-handler checks in
conversation creation and first-run entry. It retains real widget handlers,
providers, errors, authorization, persistence, concurrency and known regressions.
No production, dependency, CI, timeout, retry, animation or environment change.

| Scope | Original cases | Final cases | Change |
| --- | ---: | ---: | --- |
| `conversation_creation_test.dart` | 19 | 12 | Three DELETE Back duplicates, four MERGE sources; six local fixtures |
| `first_run_entry_test.dart` | 26 | 24 | Two MERGE sources into existing complete workflows |
| Combined affected owners | 45 | 36 | Nine fewer registrations, no new cases |
| Complete Flutter suite | 1871 + 4 skips | 1862 + 4 skips | Same 227 discovered runners |

The [45-row decision inventory](flutter-onboarding-ui-test-inventory.md) identifies
**every original source file + full runtime describe/test path**, protected
contract, KEEP/DELETE/MERGE/REWRITE decision and retained replacement. Six MERGEs
transfer every source assertion to its original observation phase in a retained
case; three DELETEs accept loss of redundant independent Back snapshots. Green
remaining tests alone do not justify any deletion.

## Decisions and protected boundaries

All three bare Back cases exercise one StartStep TextButton callback and
NewSessionPanel._backToMenu, with generic index-based visibility in StartPages.
Chat retains its stronger same-chat Back-during-Open regression; channel retains
its same-channel typed-text roundtrip. The link Back representative explicitly
asserts StartMenu, hidden step and all four cards. Their exact names/owners are
in the inventory and all ran in this round. Group has no separate Back handler
or known group-specific Back regression. Its duplicate is removed on shared
source/contract evidence, **not** a claim that the link test can catch every
future group-only constructor miswire. That individual wiring check is a stated
coverage tradeoff; add a focused test if group-specific Back behavior appears.
No replacement points at the old per-card copies deleted in `93ef2f30`.

Six MERGEs:

- DM create's eight saved-card/URI/action/hidden-chat assertions run before the
  existing Copy action; the same seeded bridge is explicitly bound locally.
- Group empty/whitespace/enabled checks precede the existing create, returned
  URI/footer, clipboard, explicit list refresh and reset sequence.
- Channel keyboard input and example input share a fixture, with an explicit
  empty/disabled reset before the chip so its false→true transition is retained.
- Generic channel success's four assertions run in the normalized-name
  regression, followed by its exact raw `#News`→returned `news` route assertion.
- Name-save refusal is injected after valid name input and initial setup,
  preserving error + name-step checks, then the original successful retry and
  complete device/network/finish/Sessions suffix. Empty initialized profile and
  trimmed `Juno` are identical at the failing save; initialization is not failed.
- Pending native Open is held inside the actual create→Open→DM workflow using
  existing ScriptedEngine.hold/release. Real menu, shared bridge/gateway store,
  three pending assertions before release and all final route assertions remain.
  Release runs the normal fake admission update; it does not inject a canned
  response that skips that effect.

Six cases use the existing `pumpScreen` fixture with their real step/provider
implementation: DM Copy/typed-error/retry, group validation-create-reset/error,
and channel typed error. The original 1280×900/DPR1/reset and clipboard cleanup
remain. There is no new shared helper, fake API, controller substitute or test
abstraction. Failure before/after list-count comparisons stay meaningful even
when the unrelated rail's initial read is gone (group 0→0 instead of 1→1).
Successful explicit post-create/post-join refresh still requires exactly two
reads, so provider initialization alone cannot satisfy it.

Five creation cases keep real menu/router fixtures: DM Open, group Open,
normalized channel success, channel lead/security/input checks, and channel
string-error/no-navigation. Parent-owned lead text and the independent negative
navigation assertion therefore keep their actual context. InlineError retains
its standalone exact live-region semantics check. Lower classifier/provider
coverage does not substitute caller-specific typed-error UI wiring.

Entry retains startup-completed versus newly-completed gate branches, unreadable
preferences and restored steps, all six dynamic Russian large-text reflow cases,
linking/proof/cancellation/approval races, disabled delivery controls, deep-link
intake, same-panel Back and disposed-route late Open, selective saved-invite
replacement, list invalidation and long-URI copy/layout. Seeded-locale viewport
checks do not replace live locale changes. No external validation is replaced
by Dart types, and no useful flaky test is deleted.

## Source/history and anti-growth checks

Read root/nearest instructions, Architecture, ADRs 0010/0036/0042, test/analysis
configuration, existing test-policy and CI. CI continues ordinary `flutter test`;
no discovery lists change. Root owns every tracked edit, compiler/test process,
measurement and commit. Read-only reviewers own creation, entry and lower-level
coverage; a later reviewer independently audits decisions, raw metrics and docs.

History includes `95fb62af` (shared start-menu steps/name validation), `93ef2f30`
(previous pruning; not circular replacement evidence), `edd593ad` (durable saved
invitations), `46202d8a` (late Open guards), `efb9a7f5` (onboarding caller error
classification despite existing classifier tests), `d16cd642` (persistent inline
errors), `4d98f271`/`24b14f63` (explicit successful list refresh), `49d1a1d0`
(IVO-50 normalized route), `4a46800a` (previous assertion transfers), and
`82f123bb` (save failure/full setup). Available commits and implementations were
reviewed before removing registrations; no regression contract is deleted.

Edits select exact file + full registration path through Dart analyzer AST,
remove whole registration statements and transfer complete statements/assertions.
A transitive immutable audit checks baseline→pruned→six-fixture→final snapshots:
all six MERGE assertion sequences and retained target flows, every unrelated
complete test declaration/helper, all six local fixture callback bodies and
explicit routed exceptions. Final source bytes/modes match that snapshot.
Source proofs complement runtime full-name/result/skip/multiplicity comparison.
Four orphaned imports are removed; no orphaned fixture/helper remains.

AGENTS now states the narrow real-widget versus real-route boundary. Existing
policy/linter capabilities remain sufficient: focused cases are forbidden;
new skips/todos, overrides and waits need reason/issue; case libraries need one
scoped owner. No new linter or policy abstraction. Seven existing allowed/
forbidden/ownership/exception examples pass. Limits: all changed tests are under
400 lines; existing long declaration-only main blocks remain size exceptions,
keeping complete behavior proofs together rather than extracting test wrappers.
New/changed local pump helpers remain below 50 lines.

## Module first, then expansion

The initial command was `flutter test --machine
test/features/onboarding/conversation_creation_test.dart`: 19 pass, 16.558 s
complete wall / 25.269 child CPU s. First prune-only run: 12 pass, 17.511 s /
25.730 CPU s; repeat: 15.971 s / 23.398 CPU s. Thus fewer cases alone did not
establish the requested speed improvement. Initialization in the first visible
case moves to the next first case; its old body duration is not a saved budget.

A seven-local-fixture pilot passed 12 in 11.803 s / 17.073 CPU s, but review found
its generic channel error's no-navigation assertion lacked the literal real
router. That case was restored to the route fixture. The seven-fixture timing
is retained as a rejected pilot, **excluded from the accepted comparison**.

The final six-local-fixture module passed ordinary and seed42 checks, plus the
unchanged `start_actions_test.dart` Back replacements (34 total). Only after
that source/contract/runtime verification did entry expand. The entry changes
then passed combined normal and seed42+Back checks (36 / 58 total).

Accepted same-command module comparisons below use original A and final
six-fixture B; creation measurements precede the two entry assertion transfers.
The combined comparison includes the complete final implementation. Normal
measurement order for each was A1/B1/B2/A2, with seed checks and analysis between
samples; the separate prune/seven-fixture trials also preceded creation B1.
These are module observations, not a complete-suite speed claim.

| Run | Full command wall s | Child CPU s | File interval sum s | Loading sum s | Visible body sum s |
| --- | ---: | ---: | ---: | ---: | ---: |
| creation-a1 | 16.558 | 25.269 | 14.475 | 4.044 | 10.414 |
| creation-b1 | 13.204 | 20.005 | 11.196 | 4.361 | 6.820 |
| creation-b2 | 12.085 | 18.805 | 10.068 | 4.033 | 6.023 |
| creation-a2 | 17.246 | 26.697 | 15.203 | 4.703 | 10.484 |

Creation medians: wall **16.902 → 12.644 s** (-25.19%), CPU **25.983 → 19.405 s** (-25.32%).

Combined command: `flutter test --machine` followed by
`test/features/onboarding/conversation_creation_test.dart` and
`test/features/onboarding/first_run_entry_test.dart`.

| Run | Full command wall s | Child CPU s | File interval sum s | Loading sum s | Visible body sum s |
| --- | ---: | ---: | ---: | ---: | ---: |
| scope-a1 | 16.654 | 40.102 | 29.135 | 9.293 | 19.815 |
| scope-b1 | 15.073 | 32.118 | 23.304 | 8.543 | 14.729 |
| scope-b2 | 15.933 | 32.757 | 23.904 | 8.789 | 15.080 |
| scope-a2 | 16.547 | 40.126 | 28.535 | 8.397 | 20.098 |

Combined affected scope medians: wall **16.600 → 15.503 s** (-6.61%), CPU **40.114 → 32.437 s**
(-19.14%).

## Complete-suite comparison

The prior completed full capture at the identical baseline test source was
`.git/test-audit/voice-state-next/whole-b2.jsonl`: 1871 pass + four native skips,
227 runners, 128.081 s wall / 1064.583 CPU s. It is provenance only, not pooled
with fresh measurements. After module verification, fresh full commands run
consecutively **A/B/B/A**, always exactly `flutter test --machine` with ordinary
settings. Guarded snapshots restore original test bytes/modes for A and exact
final candidate for B, refusing unexpected edits and restoring final source.
Root runs no other compiler/test/analyzer/formatter concurrently. Other host
agents' workload and caches are uncontrolled; CI/env/concurrency are unchanged.

| Run | Full command wall s | Child CPU s | File interval sum s | Loading sum s | Visible body sum s |
| --- | ---: | ---: | ---: | ---: | ---: |
| whole-a1 | 131.575 | 1071.558 | 1001.685 | 419.738 | 580.273 |
| whole-b1 | 128.582 | 1049.306 | 977.829 | 407.648 | 568.401 |
| whole-b2 | 143.602 | 1177.800 | 1097.319 | 460.463 | 635.158 |
| whole-a2 | 141.609 | 1157.349 | 1079.328 | 445.809 | 631.775 |

Balanced complete-series medians: wall **136.592 → 136.092 s** (-0.37%), CPU **1114.453 → 1113.553
s** (-0.08%). File interval sums 1040.506 → 1037.574 s. Two samples per state mean the median
equals the mean. Forward and reverse comparisons do not both favor the candidate in wall and CPU.
These data do not establish a stable whole-suite speedup; the median difference is an observation
under shared-host variation, not a causal guarantee. Unchanged original controls differ by 10.033
s wall; the difference between state medians is 0.500 s. The two identical candidate runs differ by
15.019 s wall; neither candidate sample is discarded.

Wall covers the complete CLI, including startup. CPU is completed child/
descendant user+system time (RUSAGE_CHILDREN). File sums span each runner's first
start through last completion; loading is the hidden loader; visible bodies
exclude hidden/skipped cases. Those intervals overlap across parallel runners,
so file/loading/body sums are neither elapsed nor exclusive CPU. No universal
CI, cold-build or hardware/native speed guarantee follows from these samples.

## Verification and limits

- Normal and seed42 scopes pass. Exact counters prove the expected nine original
  registrations disappear and every other file/full name/result/skip reason/
  multiplicity stays. Declared Back replacements and critical entry races run.
- Fresh balanced full runs pass: A1871/B1862, same four native skips/reasons,
  227 owners in both states; no original/candidate failure is classified away.
  No baseline-failure worktree reproduction is required.
- `flutter analyze`: no issues (10.7 s), including unused imports/elements/dead
  code. No separate unused-code tool is configured. The unused gateway import
  found by review is removed before final source capture/checks.
- `dart format --output=none --set-exit-if-changed lib test integration_test`:
  816 files, zero changes. Existing test policy + seven examples pass.
- Immutable AST/source/mode proof passes; no changed production/public API,
  schema/dependency, CI/discovery, native binding or Moss source.

The four unchanged conditional skips are all in
`test/gateway/real_bridge_dispatch_test.dart` with reason
`native libs not built: mosh-core/target/release/mosh_core.dll / moss-runtime/moss.dll`:

- `undecodable attachment bytes cross as the typed error on every kind`
- `dm: send lands in the DM runtime; a missing id answers typed`
- `channel: send lands in the channel runtime`
- `group: send lands in the group runtime; after leave the lookup misses`

Actual native/device/OS and Rust/integration suites were not run; their
sources/contracts are unchanged. Optional preview/
font/screenshot modes were not exercised. Seed42 does not cover every ordering.
No mutation-test or coverage-percentage result is claimed; production is untouched
and retained behavior protection is established by explicit phase/source proof.

Changed files: `test/features/onboarding/chat_create_screen_cases.dart`,
`group_create_screen_cases.dart`, `channel_join_screen_cases.dart`,
`first_run_wizard_cases.dart`, `pending_invitation_cases.dart` (all in the same
onboarding test directory); `AGENTS.md`, `docs/testing.md`, this report and
`docs/Proposals/flutter-onboarding-ui-test-inventory.md`. No file is deleted.
Historical audits retain their original names/results. Local raw JSONL, command,
CPU/wall records, snapshots, AST tools and independent reviews are under
`.git/test-audit/onboarding-ui-prune/`, outside tracked files. Local Conventional
Commit only; no push, deploy, publication or tracker write.
