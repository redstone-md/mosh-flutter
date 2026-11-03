# Scripted-double runner experiment: rejected

Baseline: `aa8f34294de0fd4a954f195a9085351cae0d3eff` (clean tree).
Outcome: restore the original self-test files. One fewer process did not produce
a dependable reduction in whole-suite execution cost. No test, assertion,
production implementation or fixture change is retained; this report is the
only tracked change.

## Scope, implementation and isolation

The candidate moved `scriptable_bridge_test.dart` and
`scriptable_gateway_test.dart` to sibling `*_cases.dart` libraries and registered
their synchronous `main` functions under separate groups in a ten-line
`scripted_doubles_test.dart`. This reused the existing owner-checked runner
pattern. It kept all eighteen self-tests and their private library scopes.
One header-comment filename changed; every other byte of both sources matched
the baseline. No fake implementation, helper, dependency, clock, timeout, retry
or CI command changed.

`conversation_cases_test.dart` has two widget tests that initialize the widget
binding; it stayed in its own process. The merged self-tests used plain `test`,
fresh per-test objects, instance-owned scripting queues/maps and conversation
maps. They did not initialize a binding/native runtime, create HTTP clients or
servers, hold futures, install hooks or run background timers. Their native
status is a canned Dart DTO, not a native probe. Bridge instances allocate an
unlistened broadcast controller; these cases never subscribe or start reporting.
The source/isolation review was separate from green test results.

ADRs 0013/0025 explain the shared bridge/gateway state. Known contract histories
`76106e59` (custom mesh), `a781a940` (organization state) and `67a0923f` (typed
bridge errors) were reviewed. All were preserved. No tracker writes occurred.

## Case ledger

All original paths below have no describe group and remain runnable at their
original files after restoration. Final decision: KEEP every scenario. The
candidate added only `scriptable_bridge`/`scriptable_gateway` group prefixes
under the common runner; it removed no scenario. Its prefix/path mapping was
checked against every complete test outcome, including name multiplicity.

### `test/support/scriptable_bridge_test.dart`

| Full test path | Contract | Decision |
| --- | --- | --- |
| `a failed organization leave retains its previous snapshot` | Refused mutation preserves shared organization data. | KEEP |
| `accepted organization groups are shared with the gateway` | Accepted group is visible through both surfaces with its org identity. | KEEP |
| `joining an organization retains the snapshot for list and poll` | Join populates the shared organization state. | KEEP |
| `leaving an organization removes it from later lists` | Successful leave removes the organization. | KEEP |
| `new invitation retains its custom mesh` | Known custom-mesh regression on newly created pending invites. | KEEP |
| `organization DM offers create sessions shared with the gateway` | Shared offered sessions, field values and distinct IDs. | KEEP |
| `saved invitation retains its custom mesh` | Known custom-mesh regression on seeded pending invites. | KEEP |
| `the test bridge createInvite -> listSessions -> leave round trip` | Invite/list/leave share one conversation lifetime. | KEEP |
| `the test bridge joinChannel falls back to the canned snapshot` | Unseeded channel path remains usable in the fake. | KEEP |
| `the test bridge nativeRuntimeStatus returns real readable fields` | Canned native DTO supports actual field reads, including OpenMLS results. | KEEP |
| `the test bridge scripts a facade failure as the real bridge error` | Failure preserves generated error kind and runtime message. | KEEP |
| `the test bridge setVpnBypassConsent stores what getVpnBypassConsent reads` | Consent set/read/clear state. | KEEP |
| `the test bridge shares the gateway double's conversation state` | Seeding/acceptance is visible across facade and gateway. | KEEP |

### `test/support/scriptable_gateway_test.dart`

| Full test path | Contract | Decision |
| --- | --- | --- |
| `an unseeded channel poll falls back to the canned snapshot` | Gateway fallback snapshot. | KEEP |
| `group rename updates the shared poll and list state, not personal names` | Group rename updates both views without corrupting personal names. | KEEP |
| `the test gateway DM sendAttachment records the call` | Recorded attachment target and argument keys/values used by callers. | KEEP |
| `the test gateway dismissDmOffer records the offer host` | Recorded offer host and ID. | KEEP |
| `the test gateway send -> poll -> leave round trip` | Gateway append/poll/removal state changes. | KEEP |

## Measurements

Linux, Flutter 3.44.7 / Dart 3.12.2, one workspace and warm dependency/native-hook
caches. No other suite, analyzer or audit compiler ran concurrently with measured
commands. Ordinary source reading and report writing continued. Do not transfer
these timings to CI hardware or cold native builds.

Bounded command: `flutter test test/support --reporter json`. All runs passed
the same 20 tests: eighteen self-tests and two separate widget harness tests.
Discovery changed from three processes to two. First, three controls and three
candidate runs were measured serially; a follow-up used A/B, B/A, A/B pairs to
check whether the first result was drift. Both cohorts are retained below.

| Cohort | Wall samples, before (s) | Wall samples, candidate (s) | Median wall before/after | Median CPU before/after |
| --- | --- | --- | --- | --- |
| Initial serial | 7.656 / 7.734 / 7.630 | 7.938 / 7.962 / 9.192 | 7.656 / 7.962 | 13.151 / 14.053 |
| Alternating pairs | 8.448 / 8.332 / 8.480 | 7.798 / 8.425 / 7.276 | 8.448 / 7.798 | 14.695 / 13.120 |

The cohorts disagree: initial serial medians get worse, while paired medians
improve and two of three pairs favor the candidate. This is not enough to
promise a local speedup without qualification.

Full command: `flutter test --reporter json`. Three pairs used A/B, B/A, A/B
order. Original files were restored byte-for-byte from Git for controls; the
candidate was restored from saved bytes. Hashes, backups and `finally`
restoration protect the owned files. Unchanged states were not rewritten in the
full pairs. Flags/concurrency were identical. Every run passed **1932 tests with
the same 4 native-library skips and zero failures**. Processes: **268 -> 267**.

| Full measurement (seconds) | Original | Candidate |
| --- | ---: | ---: |
| Wall samples | 146.271 / 150.308 / 152.938 | 147.074 / 150.014 / 159.147 |
| Median total wall, launcher/hooks included | 150.308 | 150.014 |
| Median completed-child CPU | 1226.421 | 1234.475 |
| Median sum of file spans | 1143.013 | 1146.940 |
| Median sum of loading spans | 480.358 | 478.630 |
| Median sum of visible test-body spans | 660.885 | 666.532 |

Full median wall changes **-0.2%**; CPU changes **+0.7%**. A negligible wall
difference with increased median CPU and contradictory local cohorts does not
establish the requested execution-cost improvement. Fewer discovered processes
alone are not proof. The candidate is rejected. The cause of timing variation
is not established. Parallel file/loading/body spans are not total wall or CPU
time; independently computed medians need not add up.

## Verification and restored state

- Entire-source comparison preserved both case libraries, except one header
  reference. The scoped and complete file/full-name/result/skip Counters matched
  in every run after only the two explicit candidate-prefix mappings. Counts
  alone were not used to assert safety.
- Candidate analysis, formatting (801 files, zero changes), test-policy and
  whitespace checks passed. The owner guard covered both case libraries; no
  custom lint rule or historical exception was added. No baseline failures.
- The original test sources and documentation are restored byte-for-byte.
  Candidate case files, runner and documentation pointer are removed. The last
  successful original full control exercises this exact test source state.
  Final analysis and policy checks passed after restoration; formatting checked
  800 files with zero changes. The working-tree source comparison is exact.
- Native/platform integration and physical hardware are not checked locally.
  Production, dependencies, bindings and platform/environment gates are unchanged.
- Final changed file: this report only. No push, deployment or tracker write.

Raw JSON, commands, source hashes/snapshots and verification scripts remain in
`.git/test-audit/doubles/`, outside the working tree and index.
