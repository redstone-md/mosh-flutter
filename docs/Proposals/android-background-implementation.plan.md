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
   before changing public APIs, dependencies or schemas. Do not edit Moss.
5. Work through the remaining dependency frontier using separate task branches
   and merge verified changes into the integration branch. Keep each layer usable.
6. Review the integration against standards and the complete spec, run the
   relevant real-dependency checks and perform physical Android acceptance.

## Ownership

- IVO-133 worktree: Android runtime/Activity/media ownership and its tests/docs.
- IVO-147 worktree: Android resource collector, command-boundary tests and guide.
- History proposal worktree: history contract proposal documents only.
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
