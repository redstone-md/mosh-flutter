# Bounded Mosh+ UI runner

Baseline: `5f164f65917e477a4ab005d60e83ea7e9c645ba6`, initially clean.
Four related UI libraries share one synchronous entry point. All ten scenarios,
assertions, helpers and fixtures remain; the case files retain their exact
original bytes and modes. No DELETE, MERGE or fixture rewrite is involved.

| Scope | Before | After |
| --- | ---: | ---: |
| Selected UI cases | 10 | 10 |
| Selected UI runners | 4 | 1 |
| Entire Mosh+ folder cases / runners | 32 / 9 | 32 / 6 |
| Complete Flutter cases / native skips / runners | 1858 / 4 / 227 | 1858 / 4 / 224 |

## Contract and isolation evidence

Read AGENTS, Architecture, ADR 0047, test/analysis/CI configuration, all four
libraries, Plus provider/controller/card/badge wiring, shared pump helpers,
ForegroundPoller and native/billing fakes. Relevant history includes `aa8a085f`,
`3b5b2ca1` and `918c0cf5`. No regression or error/security/expiry/storage assertion
is removed. Root owns edits, measurements and commits; an independent read-only
reviewer checks implementation, immutable copies, isolation and raw outcomes.

The new `plus_ui_test.dart` only imports the four sibling case libraries under
namespaces and registers `group('stem', module.main)`. The existing policy guard
requires exactly one scoped owner for every case library. Byte/mode equality
with original Git blobs proves callback, assertion, helper, import and fixture
preservation independently of green runs. Exact outcome Counters compare source
file/full test name/result/skip reason/multiplicity after removing only the four
new source-stem prefixes and mapping their owner back to the original files.

Offer/user badges retain native provenance, legacy channel rejection, DM identity
and expiry checks. Their injected native snapshots do not reach billing. Store
membership cases preserve the explicit Windows variants, real ForegroundPoller,
one-second interval and three seconds of controlled widget time; billing must
remain uninitialized. Provider scopes/containers and the poller's disposal stay
local. TargetPlatformVariant restores its previous platform override afterward.
The storage case retains delayed catalog delivery, real SettingsContent,
PageStorage scroll offset, disclosure and unmount/reopen checks with its original
fake commands/catalog. Shared catalog maps are only read by these scenarios.

Keep `plus_mainnet_billing_test.dart` and `plus_entitlement_test.dart` in their
separate original workers: their real local HTTP contracts must not inherit a
widget binding's HTTP override. Checkout, rendered QR/image decoding and the
remaining Plus contract owners are also untouched. Folder and full runs execute them.
Imports of generated native types do not call Rust; the selected UI traces never
initialize appDataDir, native runtime or real HTTP. CI still discovers the normal
`*_test.dart` entry points. No executable consumers of the four old paths were
found; the historical issue-70 review keeps its historical path reference.

## Exact retained case ledger

All rows are KEEP: only the owner and source-stem group prefix change.
New runtime owner for every row: `test/features/plus/plus_ui_test.dart`. The final column names its exact full group/test path.

| Original file / full test path | Protected contract | Decision / new full path |
| --- | --- | --- |
| `test/features/plus/plus_membership_only_test.dart` / `a store that does not sell Mosh+ shows a membership synced from a linked device (variant: TargetPlatform.windows)` | Synced membership remains visible/toggleable without checkout or billing initialization. | KEEP; `plus_membership_only a store that does not sell Mosh+ shows a membership synced from a linked device (variant: TargetPlatform.windows)`. Complete source bytes/mode preserved. |
| `test/features/plus/plus_membership_only_test.dart` / `a store that does not sell Mosh+ shows no checkout to a non-member (variant: TargetPlatform.windows)` | Unsupported store shows no checkout/payment/recovery/details and never initializes billing across poll ticks. | KEEP; `plus_membership_only a store that does not sell Mosh+ shows no checkout to a non-member (variant: TargetPlatform.windows)`. Complete source bytes/mode preserved. |
| `test/features/plus/plus_membership_only_test.dart` / `a store that does not sell Mosh+ still shows peer badges` | Unsupported store retains verified peer badge display. | KEEP; `plus_membership_only a store that does not sell Mosh+ still shows peer badges`. Complete source bytes/mode preserved. |
| `test/features/plus/plus_offer_test.dart` / `offer badge requires native provenance: false` | An unverified offer cannot borrow a paid peer badge. | KEEP; `plus_offer offer badge requires native provenance: false`. Complete source bytes/mode preserved. |
| `test/features/plus/plus_offer_test.dart` / `offer badge requires native provenance: true` | Verified offer provenance permits the matching native peer badge. | KEEP; `plus_offer offer badge requires native provenance: true`. Complete source bytes/mode preserved. |
| `test/features/plus/plus_settings_storage_test.dart` / `profile scroll and delayed payment details restore independently` | Delayed catalog and payment disclosure survive profile unmount/reopen without corrupting scroll PageStorage. | KEEP; `plus_settings_storage profile scroll and delayed payment details restore independently`. Complete source bytes/mode preserved. |
| `test/features/plus/user_plus_badge_test.dart` / `a claimed legacy channel author cannot borrow a verified badge` | Unsigned channel author claims are rejected; native-authenticated metadata permits badges. | KEEP; `user_plus_badge a claimed legacy channel author cannot borrow a verified badge`. Complete source bytes/mode preserved. |
| `test/features/plus/user_plus_badge_test.dart` / `legacy DM messages use the authenticated conversation badge` | Legacy DM presentation uses the authenticated conversation identity. | KEEP; `user_plus_badge legacy DM messages use the authenticated conversation badge`. Complete source bytes/mode preserved. |
| `test/features/plus/user_plus_badge_test.dart` / `own badge checks expiry even when the last native read was active` | Local expiry suppresses stale active own evidence. | KEEP; `user_plus_badge own badge checks expiry even when the last native read was active`. Complete source bytes/mode preserved. |
| `test/features/plus/user_plus_badge_test.dart` / `shared badges expire and conversation titles stay ordinary` | Peer evidence removal updates badges; group/channel titles do not inherit a DM badge. | KEEP; `user_plus_badge shared badges expire and conversation titles stay ordinary`. Complete source bytes/mode preserved. |

## Scoped comparison

Initial validation of the four original paths passes ten cases in 10.162 s wall,
21.077 s child CPU. The single new driver passes the same normalized ten in
8.883 s wall, 13.122 s CPU. Those argv differ by necessity and are validation
captures, not the basis for the speed comparison below.

Formal command in **both** states: `flutter test --machine test/features/plus`.
Three serial pairs use A/B, B/A, A/B; every run passes the same 32 cases. Guarded
snapshots switch only the nine owned test paths and reject unknown source bytes;
candidate source is restored afterward. All samples are retained.

| Run | Complete wall s | Child CPU s | File sum s | Loading sum s | Visible body sum s |
| --- | ---: | ---: | ---: | ---: | ---: |
| plus-a1 | 11.548 | 34.385 | 59.955 | 49.060 | 10.874 |
| plus-b1 | 10.690 | 27.105 | 40.442 | 32.169 | 8.241 |
| plus-b2 | 12.729 | 32.129 | 47.127 | 37.480 | 9.619 |
| plus-a2 | 12.059 | 36.642 | 62.747 | 49.776 | 12.943 |
| plus-a3 | 11.749 | 34.851 | 59.148 | 46.694 | 12.429 |
| plus-b3 | 11.281 | 28.404 | 41.395 | 33.108 | 8.262 |

Scoped medians: wall **11.749 → 11.281 s** (-3.98%), CPU **34.851 → 28.404 s** (-18.50%).
Two of three pairs favor the candidate for wall; all three favor it for CPU.
Do not turn the summed loading/body reduction into elapsed seconds saved.

Candidate folder seed 42 also passes all 32, with the exact same normalized
Counter. Timed commands run serially with ordinary caches/settings; root starts
no other test/compiler/analyzer/formatter alongside them. Other agents use the
host, so these are bounded observations rather than a CI/hardware guarantee.

## Complete-suite comparison

After module/static validation, four serial ordinary `flutter test --machine`
commands use **A/B/B/A**, restoring exact original or candidate source for each.
The source guard also refuses unexpected tracked/untracked edits outside this
round. Packages, production, CI, concurrency, platform gates and timing defaults
stay unchanged. No failure is classified as pre-existing; all commands succeed.

| Run | Complete wall s | Child CPU s | File sum s | Loading sum s | Visible body sum s |
| --- | ---: | ---: | ---: | ---: | ---: |
| whole-a1 | 153.613 | 1121.551 | 1172.056 | 462.672 | 706.921 |
| whole-b1 | 132.357 | 1052.937 | 1009.611 | 418.804 | 588.976 |
| whole-b2 | 135.979 | 1057.927 | 1037.720 | 420.976 | 614.726 |
| whole-a2 | 152.456 | 1111.989 | 1163.966 | 455.606 | 705.948 |

Full medians: wall **153.034 → 134.168 s** (-12.33%), CPU **1116.770 → 1055.432 s** (-5.49%).
File sum medians: 1168.011 → 1023.666 s.
With two samples/state, median equals mean. Both forward and reverse controls favor the candidate for wall and CPU.
These observed savings do not isolate shared-host/cache effects or guarantee CI performance.
All four normalized full Counters match: 1858 passes, the same four native skips
and exactly 227 original / 224 final runners. No test scenario or assertion is removed.

Selected owner file-span medians sum to 13.0110 → 5.0375 s; the other 223 unchanged owners sum to 1155.0000 → 1018.6280 s.
These overlapping intervals are not per-owner CPU or critical-path wall.
Untouched-owner changes are not isolated from scheduling, cache and shared-host
effects. The complete elapsed difference must not be presented as guaranteed
seconds directly saved by three fewer runners.

Wall is the entire command, including launcher/native hooks. Child CPU is
completed descendant user+system time (RUSAGE_CHILDREN). File spans cover loading
through final suite completion; loading and visible non-skipped case intervals
are also reported. Intervals overlap under parallel execution: sums are neither
elapsed nor exclusive CPU, and independently calculated medians need not add.
First-case initialization can move to the next case without disappearing.
No cold-build, physical-device or universal performance claim is made.

## Verification and limits

- Four source copies match original Git bytes/modes; the new driver contains only
  four imports/groups and the standard Flutter test import. No orphaned fixture
  or import is created. Every case library has exactly one scoped owner.
- Original/pilot ten-case Counters, six 32-case folder captures, seed 42 and four
  complete captures pass exact normalized identity/result/skip comparisons.
- `flutter analyze`: no issues (10.1 s), including type/lint/unused import,
  element and dead-code diagnostics; no separate unused-code tool is configured.
- `dart format --output=none --set-exit-if-changed lib test integration_test`:
  817 files, zero changes. Policy, seven policy examples and diff checks pass.
- Every case file is below 400 lines, the driver is 14 lines. Existing long test
  declaration blocks/scenarios are copied unchanged; no new long function/type.
- No baseline failure occurred, so no baseline-failure worktree is needed.
  No Rust/native/Moss preparation or binding regeneration is needed for these
  scripted widget traces. No new coverage percentage or mutation result is claimed.

Existing lint/policy coverage is sufficient: no new focus, skip, todo, timeout,
retry, sleep, rule, test abstraction or exception is added. AGENTS already
requires valuable contracts, scoped ownership and policy checks. No production,
dependency, schema, public API, generated binding or Moss source changes.

Risks: the ten cases now share a worker, so future process-global mutations need
careful cleanup and compatible isolation. Seed 42 and local ownership evidence
do not prove every possible ordering. Full names gain the documented group
prefixes; use the new driver or explicitly run a sibling case library to debug.
Native/device/live-payment/Rust integration is unchanged and unrun. The four
ordinary native skips retain their original DLL gate names/reasons/multiplicity.

Those four skips are all in `test/gateway/real_bridge_dispatch_test.dart`:

- `undecodable attachment bytes cross as the typed error on every kind`
- `dm: send lands in the DM runtime; a missing id answers typed`
- `channel: send lands in the channel runtime`
- `group: send lands in the group runtime; after leave the lookup misses`

Their unchanged reason is `native libs not built: mosh-core/target/release/mosh_core.dll / moss-runtime/moss.dll`.
The conditional media-kit thumbnail probe actually passes and is not a fifth skip.

## Changed files

- Exact sibling renames under `test/features/plus/`: `plus_offer`,
  `user_plus_badge`, `plus_membership_only`, `plus_settings_storage`, each from
  `*_test.dart` to `*_cases.dart`.
- New `test/features/plus/plus_ui_test.dart` (14 lines).
- This audit and its `docs/testing.md` pointer.

Raw commands, source snapshots, JSON, measurements, preservation/Counter proofs
and independent review are private under `.git/test-audit/plus-ui-next/`.
No build artifact is committed; nothing is pushed, deployed or published.
