# IVO-132 implementation

Integration branch: `feat/android-background`.
Canonical scope and task graph: [IVO-132](https://linear.app/ivoxygen/issue/IVO-132/android-fonovye-zvonki-uvedomleniya-i-polnaya-dogruzka-istorii).
The [specification](android-background.spec.md) defines completion; individual
preparatory changes do not establish background acceptance.

## Execution

1. IVO-133 separates installation/media lifetime from Activity lifetime without
   changing the bridge, key policy or network settings.
2. Independently, IVO-147 prepares reproducible resource collection. Physical
   Android measurements and resulting numeric budgets remain required.
3. Independently, IVO-141/142 prepare exact history evidence, wire and durable
   import proposals, including the membership work completed by IVO-143.
4. Prepare concrete key migration, UI authentication, Android execution and
   Moss waiting contracts. Obtain the approvals required by repository rules
   before changing public APIs, dependencies or schemas. Moss changes use only
   the owner-approved separate worktree/PR exception, without a merge.
5. Work through the remaining dependency frontier using separate task branches
   and merge verified changes into the integration branch. Keep each layer usable.
6. Review the integration against standards and the complete spec, run the
   relevant real-dependency checks and perform physical Android acceptance.

## Ownership

- IVO-133 worktree: Android runtime/Activity/media ownership and its tests/docs.
- IVO-147 worktree: Android resource collector, command-boundary tests and guide.
- IVO-141 worktree: shared bounded recovery/persistence and channel history.
- IVO-142 worktree: own MLS staging and group evidence/recovery; reuse IVO-141.
- IVO-136 worktree: separate upstream Moss lifecycle and tests; integration pins
  a reviewed candidate without merging the upstream PR.
- IVO-137 worktree: Android waiting owner, native execution/delivery boundary
  and DM background reception; coordinate shared storage/bindings with IVO-141.
- Integration owner: global spec clarifications, this plan, key/execution/Moss
  proposals, task graph state, merging and integration review.

## Checks and risks

- Use the test seams already approved in the specification: public bridge and
  independent real installations; existing adapters for focused timing,
  permissions and presentation; actual Android application/OS observations.
- Run focused regression checks before each task commit, then integration checks
  appropriate to merged changes. Regenerate bindings only for approved API work.
- Preserve desktop bidirectional messaging, shared node/store/DEK/media ownership,
  live traffic during history recovery and existing deletion precedence.
- Do not substitute mocked lifecycle callbacks for phone battery, Doze, Keystore
  or incoming-call acceptance. At implementation start no adb device is connected.
- Keep tickets open when their required evidence, approval or upstream work is
  missing. A collector, proposal or successful build does not complete a feature.
- Waiting is automatic after setup in Mosh. Opt-in describes the application's
  integration with Moss; other Moss consumers retain their current defaults.

## Integration status, 2026-10-26

- Ownership, same-DEK migration and timed chat access are integrated. A cold
  service reuses the installation owner; key failure cannot mint another DEK.
  UI polling waits for an attached foreground view. Desktop polling keeps its
  existing behavior.
- The quiet waiting service, native notification privacy, exact call actions,
  CallStyle presentation and typed media promotion are integrated. Calls retain
  the existing ringtone/media/PiP owners; answering does not unlock chats.
  Explicit text consent uses expanded notifications, including full body text
  within Android's rendering limits.
- Channel recovery and membership-aware group recovery are integrated. Group
  imports preserve original authorship, current source/recipient authorization,
  admission and rejoin intervals, deletion precedence and the receiver's own
  MLS transitions. Independent installations exercise alternate holders,
  offline membership changes, pre-join exclusion, rejoining and erasure.
- OS transfer execution and reclamation recovery are integrated. Actual job or
  service callbacks grant execution; scheduling alone grants no byte access.
  Native per-file admission, authenticated receiver acknowledgements and partial
  checkpoints survive restart. Automatic offers do not authorize originals or
  previews. Actual Activity/access changes revoke foreground byte eligibility
  synchronously, before asynchronous Dart lifecycle hints.
- Waiting transport remains in [Moss PR #31](https://github.com/redstone-md/moss/pull/31),
  stacked on PR #30, without an upstream merge. The integration pins its verified
  production candidate `e95c498`. It confirms TCP upgrades before replacing a
  working relay and consumes recovery only on fresh authenticated relay control.
  Its complete local Go suite, race/compatibility checks, vet, WASM and C-shared
  compilation pass. The [upstream CI](https://github.com/redstone-md/moss/actions/runs/40391160098)
  passes all eight jobs at `6a055e4`; that successor changes only a test's
  authenticated carrier-readiness precondition, with no runtime source change.
  The unchanged deadline passes 100 single-CPU race repetitions. CodeAnt completed
  review of exact production `e95c498`, with all six threads resolved.
- Host policy probes, Android production/instrumentation compilation, Flutter
  analysis and focused native scenarios pass. The reviewed Flutter checkpoint
  passed 2072 tests with four skipped. The signed release APK at production
  checkpoint `e78b286e` independently passes its checksum, certificate pin,
  ARM64/API 26 manifest, non-debug flag, JNI Zero, all four native waiting/transfer
  method signatures and exports, and 16 KiB alignment. Matching artifacts and
  final CI results are recorded in [Mosh PR #101](https://github.com/redstone-md/mosh-flutter/pull/101).
  Documentation-only follow-ups do not change that production checkpoint.
- The adb collector and guide are ready. No physical Android device is connected.
  Actual Keystore migration, locked/background calls, notification actions,
  PiP, Doze, reclamation, reboot and OS-stop behavior remain acceptance gates.
  Physical phone/desktop baselines and resulting numeric budgets are still
  required. Compilation and host tests do not close these tickets.
- Final standards/spec review found and corrected new-holder history bootstrap
  and repeated manifest scanning. Independent verification closed both findings;
  changed production lines in the history review fixes have 93.6% line coverage.
  CodeAnt's final integration review was triggered once. Its validated PiP
  generation finding and six general suggestions are fixed; the earlier request
  to exclude legitimate protected navigation from access-grace use was rejected.
- Public-network group/channel notifications and incoming call actions passed
  after authenticated route controls. The final production WAN DM/transfer
  scenario passes in 119.71 seconds: an actual Waiting/Ready carrier, durable
  notifications without receiver UI polling, delivery without false reads,
  attachment offers without automatic downloads, refusal while stopped/offline,
  explicit native download completion, foreground reply and retained history
  after cold restart. The offer's ownership comes from its verified MLS signer;
  our linked devices cannot create a foreign-message notification, even with a
  spoofed display name. Real MLS/redb regressions pass, with 19/19 changed
  production lines covered. Transport regressions also check ordinary desktop
  carrier-loss recovery, refused TCP upgrades, first-frame replay and cancellation.
  Cold rendezvous latency and physical Android acceptance remain separate;
  these route-controlled checks do not prove them.

## First Pixel acceptance, 2026-10-26

The owner tested the signed `e78b286e` candidate on a Pixel 8 Pro running
Android 17 `DP11.261002.005`, with notification and battery permissions allowed.
Foreground calls ring and minimized message notifications arrive. Acceptance
found three blockers; the earlier route-controlled checks do not close them.

- Chat entry and return after expiry showed a canceled-authentication screen
  without initiating a prompt. The existing lock screen now requests chat
  authentication once per interactive entry, preserves explicit cancellation,
  and excludes temporary dialogs and an ongoing credential prompt. Two failing
  lifecycle regressions now pass; all 29 focused lock tests and analysis pass.
  Changed executable lines have 39/40 coverage. Real Pixel retesting is pending.
- One conversation notification always used `onlyAlertOnce`, so later messages
  updated the first entry quietly. New durable revisions may now alert; equal
  or stale revisions and privacy refresh stay quiet. The existing plugin builder
  and OS notification revision provide this behavior without another store.
  Actual Java/Kotlin and instrumentation compilation pass; the OS assertions
  still require a device run. Android's interruption policy remains authoritative.
- Desktop call admission becomes unavailable after waiting. An independent
  public-WAN probe with production `e95c498` reproduces authenticated DM liveness
  loss by 65 seconds despite Waiting/Ready and one carrier. Carrier teardown
  removed established virtual application paths; the next migration scanned
  only current peers and could announce Ready with nothing left to restore.
  The separate Moss work retains exact established application
  interest across carrier loss, including subscribed-only paths and partially
  migrated carriers. Recovery consumes that intent only after verified
  replacement. Cold TCP candidates require mesh admission, and failed unused
  candidates are retired without dropping useful paths. Bounded identity lookup
  also checks connected contacts and alternate carrier records within the
  existing deadline. No API, packet, dependency or persisted schema is added.
  Follow-up candidate `ae653e4` also bounds sequential known-carrier alternatives,
  preserves first authenticated relay admission order, rejects conflicting
  session bindings, and remembers at most 1024 retired session hashes. A delayed
  old control cannot become a new admission or displace the newer route. Ordinary
  explicit targets recovering a lost relay require mesh confirmation before
  accepting a cold TCP path; ordinary cold startup remains unchanged.
  Real regressions and independent review cover these corrections. Earlier
  120-second idle checks passed, including the exact repository case without
  intermediate UI polls. A subsequent 600-second endpoint call also passed,
  but its journal revealed 79-second and 170-second availability gaps. The full
  idle interval must therefore retain authenticated liveness; a final successful
  call alone is insufficient. The clean `ae653e4` run fails this stricter check:
  both installations lose liveness about 48 seconds after Waiting/Ready. It was
  stopped after that definitive failure, before the call endpoint. No extra RPC
  or traffic is used to inspect the existing logs. Full Go and all eight upstream
  [CI jobs](https://github.com/redstone-md/moss/actions/runs/40429446955) pass for
  this candidate; they do not override that runtime failure. A metadata probe
  reproduces a carrier's raw network EOF before local retirement, followed by
  failed application-path migration and a refused call after 180 idle seconds.
  The active sender's nine identity lookups return no provider records. The
  remote closure and missing rendezvous records still require causal checks.
  Follow-up real-node regressions reserve the migration budget for useful
  carriers, retain the last verified carrier within the existing three-candidate
  batch, and retire an unused failed readmission. The clean `728e070` source
  passes full Go, focused race tests, vet, WASM and independent standards/spec
  review. One private 180-second run retains authenticated liveness through
  several physical carrier losses, then receives a call, applies native Decline
  and durably receives text. Its subsequent 600-second run fails: after a raw
  carrier EOF, a new relay request reaches the desktop and its synchronous
  Accept write succeeds, but the phone does not observe the Accept before the
  existing deadline. Actual packet callbacks stop; the final call is NotReady.
  Local framed-write success does not prove remote receipt or forwarding.
  A targeted real-node pressure control can drop that exact Accept in the
  bounded mesh dispatch queue while transport-buffer drops remain zero; this
  demonstrates the diagnostic seam, not the public failure's cause. Private
  metadata will distinguish ingress, enqueue, drop and dispatch without bodies
  or additional wire traffic. A matched 180-second Active control retains
  liveness and receives the call and durable text; no background message notice
  is expected while interactive. The capped-core eviction fixture does not
  prove the public fleet's occupancy or this failure's cause. Sustained waiting
  remains open; keep the existing pin, with no upstream merge or new installer
  handoff. Physical Pixel retesting remains required.

The subsequent `124b9b3` probe isolates route-budget starvation: a stale advertised
attachment consumes the remaining lookup deadline before the eligible former
carrier can be tried. Candidate `759630d` divides that existing budget among
distinct eligible addresses, counting a matching fresh/former address once.
The real-node regression fails three times before the fix and passes five times
under the race detector afterward. Matching-address, policy, replay, cancellation
and stale-provider controls pass; independent Standards/Spec reviews find no
issues. All eight exact-source CI jobs in `40441933418` pass. An earlier identity-only room
delivery failure remains unlocalized despite 30 exact race repetitions, 15
timing-offset cases and 28 predecessor-sequence cases passing without changing
their five-second assertions.

A separate real-node regression now proves an offline-contact barrier: a useful
replacement carrier can carry an existing live conversation while the retained
offline contact prevents publication of this installation's own identity/rooms.
Clean candidate `65b6a9c` retains one verified installation carrier independently
of offline contacts. Pending recovery keeps its original intent and uses fair
shares of the existing attempt deadline. After ordinary work drains, a single
verified carrier may truthfully report Waiting/Ready while old contacts remain
pending; useful paths on another physical carrier still prevent settlement.
The existing retry owner continues pending recovery without socket churn or
Ready/Connecting flicker. Its bounded candidate rotation still tries a known
working carrier before settling for rendezvous alone. No timer, query fanout,
wire format, ABI or schema changes.

Real-node regressions fail on the original source and pass under race checking
for all three contact orders, including all offline. Fresh-sender discovery
through the replacement directory, actual bidirectional delivery, returning
contacts, same-ID replacement, publication coalescing, current policy, Active,
Stop and cancellation are covered. Original common-carrier assertions also
pass unchanged. Changed-line coverage is 170/174 (97.7%); vet and WASM pass.
Independent review reports one P2 per axis: a settled useful carrier can still
consume the entire pending-recovery budget, and unused-candidate cleanup can
retire a working rendezvous before replacement admission. Both require real
regressions and correction. All eight exact-source CI jobs in `40446308970`
pass. The clean two-installation 600-second public-network probe was stopped for these source
corrections before the call endpoint. Its saved logs already show a continuity
failure: both installations lose authentication about 65 seconds into idle.
Both native workers exited normally; the wrapper's review-stop status is not
the runtime verdict. No causal link to either review finding is established.
The probe requires a relayed
application path and one carrier before idle; no UI polling or message warms
the final call. A separate four-node check on `759630d` confirms ordinary sender
warming can discover a carrier through another directory; this does not prove
provider-record replication or arbitrary fleet-wide reachability. Neither
candidate is integrated into Mosh or offered as a fixed installer.

The two review corrections pass their focused real-node regressions, but their
combined check exposes a separate same-ID carrier handover failure, also
reproduced on pristine `65b6a9c`. A fresh matched relay session, present core
route and equal endpoint public keys precede missing single-send callbacks.
Bounded private close metadata identifies the first closure: one endpoint
replaces its physical peer and closes the old connection before the core admits
the replacement. The core handles that EOF by deleting the forwarding route;
the endpoint still considers its virtual session established. This is a local
ordering failure, not yet an attribution of the public-network idle loss.
Candidate `94d1eb8` retains old application writes until a matching Pong on the
new reader confirms counterpart admission. Captured confirmation packets replay
before the wait; refusal restores only the exact live predecessor. Private
session/stream reader keys preserve ordering, Waiting counts both physical
connections, and ordinary MaxPeers still counts identities. Authenticated relay
expiry retains application intent and wakes existing recovery. No timer, wire,
ABI, dependency or deadline changes. The combined original/new checks pass three
race repetitions in 105.880 seconds; changed-line coverage is 179/205 (87.3%),
with vet and WASM passing.

Immutable review found two P2s around EOF and worker draining: a buffered Pong
could commit a session already known closed, and the `readClosed` fast path
could bypass an unfinished replacement owner. Candidate `0c16e80` corrects both;
real EOF controls fail three times before the fix and pass ten race repetitions
after it. Both independent follow-up reviews find no remaining issues in that
four-file correction. A proposed eager relay cleanup on old EOF was rejected:
a healthy remote handover may intentionally close old before our Pong arrives.
Existing authenticated expiry feedback distinguishes actual retired routes;
local EOF alone does not.

The clean `94d1eb8` public run also fails strict idle continuity. Both actual
process mappings match the frozen library. Initial authentication takes 4.46
seconds; Waiting/Ready, one carrier and a relayed application path take 33.95
seconds. Desktop authentication is lost about 97 idle seconds later, and the
runner exits 1 before the call endpoint. Both owned workers are gone. This is a
runtime failure, not a review abort; no causal attribution to the two P2s is
established.

A bounded, private 180-second diagnostic on `0c16e80` reproduces authenticated
loss on both installations after about 141 idle seconds. Several earlier
physical carrier EOFs recover within 2–5 seconds. At the final failure, the
sender loses its newly admitted route while the receiver retains that same
virtual route over a live carrier; no authenticated close for it is observed.
The runner stops before any call/message endpoint, and both native workers
exit normally. Waiting currently skips virtual-peer probes, so carrier health
alone cannot establish end-to-end route health. A focused regression must
distinguish missing retirement feedback from failed recovery before another
long run.

Exact-source CI `40454121728` fails two controls. The cold-recovery fixture
misses legitimate immediate repair after the old route retires. The stale-hint
fixture lets the receiver reconnect to its old core, making that provider valid
again. Test-only `e0dfa7f5` holds recipient dispatch during the deliberate
Noise-only check and revokes only the old receiver/core edge while preserving
its stale provider record and origin link. The 2500 ms budget, single sends and
topology assertions remain unchanged. Follow-up CI `40456684771` passes all
eight jobs, but does not erase the intermediate one-in-ten failure.

Failure-only traces now localize that residual to pending relay admission:
same-identity physical replacement can close a carrier after its signed Request
is written but before the core dispatches it. There is no established child
route yet, so established-route handover protection does not apply. Two
real-transport regressions reproduce the loss three times each. A private
correction retains the same pending operation, signed session ID and deadline,
and sends its control through the normally admitted replacement. It adds no
payload retry, timer, public contract or topology allowance.

A third regression reproduces an obsolete failed sender deleting the pending
operation already claimed on its replacement. Genuine EOF also removes a live
pending owner, while a failed current write can incorrectly consume its entire
timeout. The corrected pending controls pass five race repetitions, including
cancellation, deadline and Stop, but initially leave one original failure in 50.

The next failure-only trace identifies two simultaneous cold TCP dials selecting
different connection halves at opposite endpoints. A caller-visible regression
reproduces duplicate physical handshakes three times. Coalescing their overlap
passes five races; the original unchanged 2500 ms case then passes 50 races in
58.795 seconds. Candidate `6cf4ed2` freezes this work in two commits, with
121/136 changed runtime lines covered, original compatibility and vet/WASM
passing. Exact CI `40463195519` fails the strict useful-carrier control: one
single-send payload is missing after migration.

The waiting side closed its retired direct path after the migration grace while
the peer kept writing there until it observed EOF; a payload in that window was
accepted locally and lost. A deterministic regression reproduces it three times.
Moss `4acfaab` sends an additive `carrier_retire` control on the exact draining
session, so the peer falls back to its established relay while the waiting side
still reads. Older nodes ignore it. Inferring retirement from relay admission
alone was rejected: ordinary nodes also open relays before seeing a new direct
path. All eight exact-head jobs pass in Moss CI `40595888450`.

Independent review finds two P2s: synchronous replay couples pending-control
writes to a shorter physical dial's completion, and the new allowlist preflight
rejects previously admitted carriers/targets after strict mode is enabled. A
separate real regression shows identity-wide coalescing can exhaust a short
fresh-address caller behind a longer stale-address dial. All three findings
have saved RED controls. Private follow-up work narrows coalescing to the same
identity and address, uses the existing tracked join tail for replay, and
preserves existing-admission exemptions without allowing new unlisted remotes.
Two of the three reproduce on `4acfaab`: a stale-address dial starves a
fresh-address caller of the same identity, and strict mode refuses relays to
peers admitted before it. Moss `34933b8` coalesces only the same identity at
the same address; `b8970bf` gates only targets that are neither listed nor
already admitted. The replay-coupling finding did not produce a caller-visible
failure and is unchanged.

Two CI flakes are also corrected. Masquerade auto-port startup bound TCP once
and failed when another process held the same UDP number; `095cbe6` retries a
fresh pairing as the plain listener already did. A lost LAN self-address tie
could re-derive the same address; `03b06d7` keeps salting until it moves.

These source diagnoses do not yet explain the entire public-network failure.
Mosh now pins `095cbe6` to test the corrected migration on the Pixel; strict
sustained-network, physical Android and measured resource acceptance remain
open.

Separately, Windows CI exposed an imported group attachment being rewritten by
the generic live-history tail without its retained preview evidence. A native
regression reproduces the same occurrence conflict and a four-second storage
check identifies the mutation. Group service now flushes live work before
history import and acknowledges the saved suffix through the existing runtime
boundary. The eight-case independent recovery suite and 110 group checks pass
locally; focused Windows checks also pass. Already affected review profiles
are repaired automatically from an authorized healthy holder, but only when
the original offer matches its protected identity, receipt and digest. Local
ownership, read state, deletions and notification acknowledgements survive;
main and preview remain undownloaded. Without that holder, recovery remains
incomplete rather than claiming success from an empty source. The repair passes
119 native group checks and nine independent-process scenarios, with 134/136
changed production lines covered. Focused Windows run `40409663932` also passes
the exact repair case, restart/export checks and three attachment-recovery runs.
The existing atomic `save_history` and `imported_history_row` boundaries exceed
the 50-line preference; retaining their commit ordering avoids an unrelated
refactor. New validators and test fixtures stay within the documented limits.

The focused native-media workflow passes three unchanged-criteria observations
on each of Windows and macOS. The subsequent full native suites pass on all
three desktop platforms; no production media fix is inferred for the earlier
intermittent failures. macOS worker teardown separately logs Cubeb aborts after
API-owned engines are retained until process exit. Relevant production and
fixture shutdown paths match `origin/main`; no matched baseline executable or
native crash stack establishes the cause or equivalent Flutter-exit behavior.
Keep this existing teardown limitation separate from background reception.
Full Mosh CI run `40432133188` and Windows diagnostics `40432133165` pass on
`2919392d`, using the retained `e95c498` Moss pin. Those results do not validate
later Moss candidates or close the public-WAN and physical-device gates.

## Approved boundaries

The [access](android-background-access-contract.plan.md),
[execution](android-background-execution-contract.plan.md),
[Moss](android-moss-waiting-contract.plan.md) and
[history](android-history-contracts.plan.md) contracts are approved. Approval
does not establish implementation or physical acceptance.

Recovery is automatic, with no administrator review UI. The owner accepted
current-authorized-holder trust for historical context, while retaining original
authorship and independent recipient-access checks. A dishonest holder and
colluding author can falsify context; receipts do not independently prove time.
Group recovery retains verified own-MLS facts and never imports another device's
private MLS snapshot. The withdrawn manual-administrator proposal is not part of
the implementation.
