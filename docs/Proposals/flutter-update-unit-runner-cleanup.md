# Bounded update-contract runner

Baseline: `d1a7c1ae369fafcb919aa07fe38a89f07486df49`, initially clean.
Three related unit libraries share one synchronous entry point. All 26 cases,
assertions, fixtures, hooks, error observations and real IO/cryptography remain.
Case libraries keep exact original Git bytes/modes. No DELETE, MERGE or fixture,
clock, timeout or retry rewrite is involved.

| Scope | Before | After |
| --- | ---: | ---: |
| Selected update cases / runners | 26 / 3 | 26 / 1 |
| Entire settings folder cases / runners | 84 / 11 | 84 / 9 |
| Complete Flutter passes / native skips / runners | 1858 / 4 / 222 | 1858 / 4 / 220 |

## Contract, regression and isolation evidence

Read AGENTS, Architecture, ADR 0045, test/analysis/CI configuration, all three
libraries, release/provider/apply/download implementations and update-assets
support. Read the previous interrupted-download audit and available history
`2723c687`, `e695b4f0`, `972eda6c`, `c8c7cef0`, `16241648`, `3527701b`.
Root owns edits, measurements and commits; one independent read-only reviewer
checks source/history, immutable copies, isolation and completed raw captures.

`app_update_contract_test.dart` imports three sibling case libraries under
namespaces and calls their synchronous mains through three scoped groups.
The existing policy requires exactly one owner per case library. Whole-file
byte/mode equality with baseline Git proves every original assertion, action,
helper, nested group, setup and teardown is kept independently of green runs.
Counter comparisons normalize only these three new group prefixes and map the
new owner to the original files; full name, result, skip reason and multiplicity
otherwise stay exact. Registration itself adds no new test abstraction.

Feed tests keep external JSON validation, pre-release selection, version ordering,
no downgrade and package/feed provider gating. Reads/package metadata are injected;
containers are locally disposed. Install tests retain Windows artifact path,
exact silent/relaunch arguments, detached mode and exit code, plus macOS handoff
and unsupported-host provider behavior. Process start/exit/file-open are injected.
The provider-only macOS case constructs/reads applier properties, never opens it.
No real HTTP, installer, Finder, native initialization or plugin request is reached.

Download tests still perform real SHA-256 and real temporary-file IO. Each test
creates its own staging directory, and group-scoped setup/teardown applies only
to that library, not to sibling provider/applier tests. No global directory,
crypto provider or widget binding is replaced. Resolved cryptography VM hashing
uses its unchanged Dart backend. All streams/operations finish before cleanup.

Keep `3527701b`'s regression fix intact: attach the expected error observer before
injecting failure; await firstHeldBody, then real progress; inject SocketException,
await controller close and the failed operation before asserting empty staging.
The prior audit reproduced the historical race in a detached worktree and checked
cleanup with a private mutation. Those are historical results, not rerun or claimed
as new mutation evidence here. No sleeps/polling/event-queue heuristics are added.

About UI and every other settings owner remain separate workers. The feature
guide's live coverage list now names the new driver and sibling cases. Historical
download-audit paths remain truthful to their original commits. No executable
consumer or CI path list needs changing; ordinary `*_test.dart` discovery remains.

## Exact retained case ledger

All rows are KEEP. Only sibling file paths, runtime owner and module group prefixes change.
New runtime owner for every row: `test/features/settings/app_update_contract_test.dart`. Existing nested group paths stay intact.

| Original file / full group/test path | Protected contract | Decision / new full path |
| --- | --- | --- |
| `test/features/settings/app_release_provider_test.dart` / `a body that is not a release is refused, not guessed at` | Malformed feed, missing fields, invalid URLs and draft-only data fail runtime validation. | KEEP; `app_release_provider a body that is not a release is refused, not guessed at`. Original source bytes/mode preserved. |
| `test/features/settings/app_release_provider_test.dart` / `a build ahead of the feed is left alone` | Newer installed build is not downgraded. | KEEP; `app_release_provider a build ahead of the feed is left alone`. Original source bytes/mode preserved. |
| `test/features/settings/app_release_provider_test.dart` / `a feed of only pre-releases still names one` | Pre-release-only feeds remain usable. | KEEP; `app_release_provider a feed of only pre-releases still names one`. Original source bytes/mode preserved. |
| `test/features/settings/app_release_provider_test.dart` / `a feed read names the version and the page, without the tag prefix` | Injected feed uses the release-list URL and returns normalized version plus release page. | KEEP; `app_release_provider a feed read names the version and the page, without the tag prefix`. Original source bytes/mode preserved. |
| `test/features/settings/app_release_provider_test.dart` / `a newer release reaches the caller` | Provider returns a newer release after reading the installed version. | KEEP; `app_release_provider a newer release reaches the caller`. Original source bytes/mode preserved. |
| `test/features/settings/app_release_provider_test.dart` / `a pre-release is a published build, and the highest version wins` | Version ordering wins over creation order; pre-releases remain eligible. | KEEP; `app_release_provider a pre-release is a published build, and the highest version wins`. Original source bytes/mode preserved. |
| `test/features/settings/app_release_provider_test.dart` / `an installation that is current reports nothing to move to` | Equal installed version yields no update. | KEEP; `app_release_provider an installation that is current reports nothing to move to`. Original source bytes/mode preserved. |
| `test/features/settings/app_release_provider_test.dart` / `an unusable row is skipped while a good one still counts` | Invalid row cannot displace a usable published release. | KEEP; `app_release_provider an unusable row is skipped while a good one still counts`. Original source bytes/mode preserved. |
| `test/features/settings/app_release_provider_test.dart` / `comparison ignores suffixes and never suggests a downgrade` | Version comparison keeps equality, suffix, short version, malformed tag and downgrade boundaries. | KEEP; `app_release_provider comparison ignores suffixes and never suggests a downgrade`. Original source bytes/mode preserved. |
| `test/features/settings/app_release_provider_test.dart` / `without a resolved check the feed is never read` | Reading package metadata alone does not reach the feed. | KEEP; `app_release_provider without a resolved check the feed is never read`. Original source bytes/mode preserved. |
| `test/features/settings/app_update_apply_test.dart` / `a host with no artifact at all installs nothing` | Provider chooses unsupported installation on an unsupported host. | KEEP; `app_update_apply a host with no artifact at all installs nothing`. Original source bytes/mode preserved. |
| `test/features/settings/app_update_apply_test.dart` / `a sandboxed macOS build hands the image over instead of installing` | Provider selects supported image handoff rather than in-place bundle replacement. | KEEP; `app_update_apply a sandboxed macOS build hands the image over instead of installing`. Original source bytes/mode preserved. |
| `test/features/settings/app_update_apply_test.dart` / `the image applier opens the verified file and nothing else` | Injected macOS handoff receives the verified image path; in-place install is false. | KEEP; `app_update_apply the image applier opens the verified file and nothing else`. Original source bytes/mode preserved. |
| `test/features/settings/app_update_apply_test.dart` / `updateCandidateFor a host with no published artifacts installs nothing` | Unsupported host yields no candidate and unsupported applier. | KEEP; `app_update_apply updateCandidateFor a host with no published artifacts installs nothing`. Original source bytes/mode preserved. |
| `test/features/settings/app_update_apply_test.dart` / `updateCandidateFor a mac install takes the image of this release` | macOS selects the current release image. | KEEP; `app_update_apply updateCandidateFor a mac install takes the image of this release`. Original source bytes/mode preserved. |
| `test/features/settings/app_update_apply_test.dart` / `updateCandidateFor a windows install takes the installer and its sidecar` | Windows selects the matching installer and its checksum asset. | KEEP; `app_update_apply updateCandidateFor a windows install takes the installer and its sidecar`. Original source bytes/mode preserved. |
| `test/features/settings/app_update_apply_test.dart` / `updateCandidateFor an artifact without a published sidecar is not installed` | Unverifiable artifact is not offered for installation. | KEEP; `app_update_apply updateCandidateFor an artifact without a published sidecar is not installed`. Original source bytes/mode preserved. |
| `test/features/settings/app_update_apply_test.dart` / `updateCandidateFor another version in the release is not this release` | Wrong-version artifacts are rejected. | KEEP; `app_update_apply updateCandidateFor another version in the release is not this release`. Original source bytes/mode preserved. |
| `test/features/settings/app_update_apply_test.dart` / `windows hands the installer its silent flags and ends the app` | Injected process seam receives exact artifact path, silent/relaunch flags, detached mode and exit code. | KEEP; `app_update_apply windows hands the installer its silent flags and ends the app`. Original source bytes/mode preserved. |
| `test/features/settings/app_update_download_test.dart` / `a checksum mismatch is refused and nothing is left behind` | Mismatched bytes fail verification and leave staging empty. | KEEP; `app_update_download a checksum mismatch is refused and nothing is left behind`. Original source bytes/mode preserved. |
| `test/features/settings/app_update_download_test.dart` / `a download that dies mid-flight leaves nothing behind` | Held-body/progress readiness precedes injected stream failure; awaited failure removes the partial file before teardown. | KEEP; `app_update_download a download that dies mid-flight leaves nothing behind`. Original source bytes/mode preserved. |
| `test/features/settings/app_update_download_test.dart` / `a download with no declared size still reports what arrived` | Progress reports received bytes with an unknown total. | KEEP; `app_update_download a download with no declared size still reports what arrived`. Original source bytes/mode preserved. |
| `test/features/settings/app_update_download_test.dart` / `a release without a usable checksum is not downloaded at all` | Invalid sidecar prevents any artifact request and staging residue. | KEEP; `app_update_download a release without a usable checksum is not downloaded at all`. Original source bytes/mode preserved. |
| `test/features/settings/app_update_download_test.dart` / `a verified artifact lands in staging and reports its progress` | Real staged bytes/hash and declared progress; sidecar is requested before artifact. | KEEP; `app_update_download a verified artifact lands in staging and reports its progress`. Original source bytes/mode preserved. |
| `test/features/settings/app_update_download_test.dart` / `parseSha256Sidecar reads the published digest and tolerates a missing name` | Digest parser accepts named/unnamed sidecars and normalizes uppercase. | KEEP; `app_update_download parseSha256Sidecar reads the published digest and tolerates a missing name`. Original source bytes/mode preserved. |
| `test/features/settings/app_update_download_test.dart` / `parseSha256Sidecar refuses a digest for another file, or no digest at all` | Wrong filename, empty digest and short digest fail runtime validation. | KEEP; `app_update_download parseSha256Sidecar refuses a digest for another file, or no digest at all`. Original source bytes/mode preserved. |

## Validation captures and count correction

Initial validation uses the three original paths: all 26 pass in 8.076 s complete
wall / 13.927 s child CPU. The new driver passes the same normalized 26 in
7.005 s wall / 10.389 s CPU. These are single validation captures, not the basis
for the paired conclusions below. All captured samples remain recorded.

The first folder control passes **84**, not an initially assumed 83. An earlier
ranking helper used broad `startswith('loading ')`, incorrectly excluding the
ordinary voice test `loading disables the microphone until enumeration completes`.
The real Counter/measurement reader already distinguishes the exact hidden loader
and retained that case; its complete 84-case Counter equals the previous full
baseline's settings subset. The count guard stopped after the successful A1,
before B1. Corrected it to 84 and explicitly resumed with that original A1 kept;
no test failed, no sample was discarded/replaced and no hidden/skip flag changed.
All complete-suite counts were unaffected.

## Selected update module: 26 cases

Reproducible Bash selector in both states:
`flutter test --machine test/features/settings/app_*_test.dart`.
The private harness uses sorted Path.glob, asserting that it selects exactly the
three original owners or the single new driver. Expanded Flutter argv therefore
differ by source file paths; flags and the exact normalized 26-case set match.
Do not call this identical expanded argv. All actual argv are recorded.

After the broader-folder captures below, three serial A/B, B/A, A/B pairs isolate
the selected module's cost. Snapshots restore exact original/candidate bytes/modes
and refuse unknown source edits; the final candidate is restored afterward.

| Run | Complete wall s | Child CPU s | File sum s | Loading sum s | Visible body sum s |
| --- | ---: | ---: | ---: | ---: | ---: |
| unit-a1 | 7.427 | 12.950 | 14.734 | 14.323 | 0.394 |
| unit-b1 | 5.890 | 8.612 | 3.870 | 3.622 | 0.232 |
| unit-b2 | 6.320 | 9.815 | 4.378 | 4.100 | 0.265 |
| unit-a2 | 7.573 | 13.190 | 14.712 | 14.276 | 0.418 |
| unit-a3 | 7.853 | 13.931 | 15.151 | 14.683 | 0.450 |
| unit-b3 | 7.590 | 11.730 | 5.437 | 5.043 | 0.368 |

Selected module medians: wall **7.573 → 6.320 s** (-16.55%), CPU **13.190 → 9.815 s** (-25.59%).
Wall favors the candidate in 3/3 pairs. CPU favors the candidate in 3/3 pairs.

## Entire settings folder: negative comparison retained

Identical expanded argv: `flutter test --machine test/features/settings`.
All six A/B, B/A, A/B captures pass the same 84 cases, including 58 outside the
selected block. This series precedes the selected-module measurements above.
Its negative result is kept separately, not pooled with or replaced by the
positive 26-case result. No cause of the folder regression is established.

| Run | Complete wall s | Child CPU s | File sum s | Loading sum s | Visible body sum s |
| --- | ---: | ---: | ---: | ---: | ---: |
| settings-a1 | 21.846 | 82.664 | 109.142 | 70.624 | 38.440 |
| settings-b1 | 21.419 | 83.646 | 99.853 | 56.753 | 43.016 |
| settings-b2 | 20.842 | 82.102 | 100.521 | 58.676 | 41.766 |
| settings-a2 | 19.806 | 79.510 | 94.410 | 55.221 | 39.128 |
| settings-a3 | 20.504 | 78.901 | 99.615 | 61.864 | 37.694 |
| settings-b3 | 18.839 | 72.637 | 96.247 | 60.897 | 35.277 |

Broader settings medians: wall **20.504 → 20.842 s** (+1.65%), CPU **79.510 → 82.102 s** (+3.26%).
Wall favors the candidate in 2/3 pairs. CPU favors the candidate in 1/3 pairs.

Folder seed 42 also passes all 84 with the same normalized Counter. This covers
the new module's test ordering and unchanged About/settings workers. Own commands
run serially with ordinary caches/settings; no own analyzer/compiler/test/formatter
overlaps a timed capture. Other agents use the same host.

## Complete-suite comparison

After module/static validation, ordinary `flutter test --machine` runs four times
in A/B/B/A order. The guard rejects unrelated tracked/untracked edits and HEAD
changes, and restores final candidate source afterward. Production, dependencies,
CI, global timing, concurrency and native gates stay unchanged.

| Run | Complete wall s | Child CPU s | File sum s | Loading sum s | Visible body sum s |
| --- | ---: | ---: | ---: | ---: | ---: |
| whole-a1 | 150.980 | 1246.800 | 1153.647 | 474.791 | 677.012 |
| whole-b1 | 138.787 | 1132.335 | 1058.454 | 440.492 | 616.257 |
| whole-b2 | 144.948 | 1123.981 | 1098.877 | 439.865 | 657.027 |
| whole-a2 | 181.158 | 1284.545 | 1388.134 | 527.413 | 857.824 |

Full medians: wall **166.069 → 141.867 s** (-14.57%), CPU **1265.672 → 1128.158 s** (-10.86%).
File sum medians: 1270.8905 → 1078.6655 s.
With two samples/state, median equals mean. Both forward and reverse controls favor the candidate for wall and CPU.
These observations do not isolate shared-host/cache effects or guarantee CI performance.
The positive selected-module result, negative settings-folder result and wide
original-source variation do not establish a stable whole-suite/CI speedup.
Retain the batch for the repeated 26-case module saving and two fewer startup
owners; do not present its full elapsed difference as an isolated patch effect.
Same-source wall spreads: original 30.177 s, candidate 6.161 s; median difference 24.202 s. All samples are retained.
All four normalized full Counters match: 1858 passes and the same four native
skips; exactly 222 original / 220 final runners. No case or assertion is removed.

Selected owner file-span medians: 5.2225 → 1.7055 s; the other 219 unchanged owners: 1265.6680 → 1076.9600 s.
These overlapping sums are not per-owner CPU or critical-path wall. Changes
in untouched owners are not isolated from scheduling, cache and shared-host
effects. Do not credit the entire elapsed difference to two fewer runners.

Wall includes the entire command and launcher/native hooks. Child CPU is completed
descendant user+system time (RUSAGE_CHILDREN). File spans cover loading through
last completion; loading and visible non-skipped case intervals are reported
separately. These overlap across workers and are neither elapsed nor exclusive CPU.
Independently calculated medians need not add. Moving first-case warmup is not
eliminating it. No cold-build, CI/hardware or universal performance guarantee.

## Verification and limits

- Three source copies match original Git bytes/modes; each case library has
  exactly one scoped owner. Only a 12-line registration driver is new Dart code.
- Initial/pilot runs of 26 cases, six selected-module and six broader-folder
  captures, seed 42 and four full captures pass exact normalized comparisons.
- `flutter analyze`: no issues (6.3 s), including type/lint and unused import,
  element/dead-code diagnostics; no separate unused-code tool is configured.
- `dart format --output=none --set-exit-if-changed lib test integration_test`:
  819 files, zero changes. Policy, seven policy examples and diff checks pass.
- Case files are 144/116/151 lines; the driver has 12. Existing long declaration blocks
  are copied unchanged; no new long function/type is introduced.
- No product-test failure is classified as pre-existing; no baseline-failure
  worktree is needed. The initial tool count-guard correction is separate from
  successful product tests. No new coverage percentage/mutation result is claimed.

Existing linter/policy coverage suffices; AGENTS already records contract/value,
scoped-ownership and timing rules. No new rule, focus, skip, todo, timeout, retry,
real delay, dependency, exception, production/schema/public API/generated binding
or Moss source change is made. No test/helper/import is orphaned.

Risks: the 26 unit cases share a worker; future process-global, native, HTTP or
widget-binding changes require compatible isolation. Seed 42 cannot prove every
possible ordering. Full test names gain the recorded prefixes; use the new driver
or explicitly run one sibling case library when debugging. Real native/device,
Windows installation, macOS handoff and live GitHub/network integration remain
unrun and unchanged. Real IO/SHA checks do not prove publisher authenticity.

Four native skips remain in `test/gateway/real_bridge_dispatch_test.dart`:

- `undecodable attachment bytes cross as the typed error on every kind`
- `dm: send lands in the DM runtime; a missing id answers typed`
- `channel: send lands in the channel runtime`
- `group: send lands in the group runtime; after leave the lookup misses`

Their unchanged reason is `native libs not built: mosh-core/target/release/mosh_core.dll / moss-runtime/moss.dll`.
The conditional media-kit thumbnail probe passes and is not another skip.

## Changed files

- Exact sibling renames under `test/features/settings/`: `app_release_provider`,
  `app_update_apply`, `app_update_download`, each `*_test.dart` → `*_cases.dart`.
- New `test/features/settings/app_update_contract_test.dart` (12 lines).
- This audit, its `docs/testing.md` pointer and the live coverage list in
  `docs/Features/settings-redesign.md`.

Raw command logs, snapshots, Counters, metrics and independent review remain
private under `.git/test-audit/update-unit-next/`. No build artifact is committed;
nothing is pushed, deployed or published.
