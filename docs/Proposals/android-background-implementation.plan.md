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
  loss by 65 seconds despite Waiting/Ready and one carrier. This is an open
  transport blocker, not a physical Android success or a proven OS restriction.
  Separate Moss candidates fix refused physical-carrier TCP upgrades and
  retirement of unresponsive virtual sessions. Their focused regressions pass,
  but candidates `95e2edc` and `e06a460` still lose the authenticated route:
  after 120 idle seconds the native call command returns `NotReady`. The latter
  also corrects bounded lookup of already-connected contacts beyond the nearest
  20 and authenticated carrier-address reuse during explicit-target recovery.
  Both peers are authenticated immediately before waiting; route loss follows
  that transition. Neither a healthy carrier
  nor those transport regressions establish sustained conversation availability.
  The authorized separate Moss PR is being investigated; no upstream merge or
  candidate pin until the actual idle-call check passes.

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
