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
  Native durable per-file admission/checkpoint integration is being completed
  on its component branch before the next complete integration check.
- Waiting transport remains in [Moss PR #31](https://github.com/redstone-md/moss/pull/31),
  stacked on PR #30, without an upstream merge. The integration pins its verified
  candidate. A further public-network group bootstrap fix is under validation;
  earlier local-tracker success does not establish public-network acceptance.
- Host policy probes, Android production/instrumentation compilation, Flutter
  analysis and focused native scenarios pass. The integrated Flutter checkpoint
  passed 2054 tests with four skipped. Whole-branch checks and signed packaging
  must be repeated after the remaining component integration; older prepared
  APKs are not candidates for acceptance of the complete feature.
- The adb collector and guide are ready. No physical Android device is connected.
  Actual Keystore migration, locked/background calls, notification actions,
  PiP, Doze, reclamation, reboot and OS-stop behavior remain acceptance gates.
  Physical phone/desktop baselines and resulting numeric budgets are still
  required. Compilation and host tests do not close these tickets.
- Earlier standards/spec and CodeAnt reviews covered the prepared layers.
  The final integration requires another complete review and resolution of
  validated findings before handoff.

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
