# Issue #94: integrate direct-peer readiness notifications

## Scope

Move Mosh's sole Moss pin from `979a634` to
`fcdc3383601cf3fb5232ba1ae1ffe262b552555e`, the tested head of
[Moss PR #30](https://github.com/redstone-md/moss/pull/30). This retains the
existing PR #29 discovery/cancellation behavior and replaces only its readiness
polling. The owner authorized continuing with integration after the separate
Moss experiment. No Moss source is edited here.

The [experiment results](https://github.com/redstone-md/mosh-flutter/blob/153ffef37ce3fb89b1fa5e5b7182324aedcee4d0/docs/Proposals/issue-94-direct-peer-wait.results.md)
establish lower allocations for the context-aware wait. They do not establish
whole-Mosh CPU savings or close desktop/Android acceptance. The candidate's
runtime matches the measured `a52072b`; final-source Linux/Windows, race,
repeated mesh, 25-node load and memory checks all passed.

## Steps and checks

1. Change only the submodule gitlink and this integration record. Preserve
   application code, Flutter/Rust bindings, storage, permissions, configuration,
   retries and public contracts. Rebuild the pinned shared library locally.
2. Run existing real-Moss directed-packet and idle-DM regressions locally.
   Run the full platform CI on the updated PR head, including calls, linked
   devices, multi-device DM, Flutter tests and bridge drift checks.
3. Build a configured Windows installer using the committed release profile,
   production PLUS issuer pin and matching native symbols. Verify immutable
   artifact identities and preserve the previous installer for comparison.
4. Reuse the measurement-only Windows GUI fixture: eight saved offline DMs,
   two groups and one channel, with acknowledged history/body inventory checks.
   Compare process CPU, external traffic and memory on one runner with the
   previous runtime; record ordering, warmup and public-topology limits.
   Public-network observations are not a deterministic traffic replay or an
   estimate of the owner's physical hardware.
5. Audit new CodeAnt comments/nitpicks, fix valid findings, and record actual
   results. Keep #94 open where physical desktop/Android acceptance is missing.

## Risk and rollback

The new subscription lifecycle may expose connection races absent under
polling; deterministic notification/cancellation tests and full connection
flows cover that boundary. A failed platform/behavior check blocks handing
out the candidate. Roll back the gitlink with an ordinary revert if needed.
No merge or release is included in this integration step.

## Initial local result

The pinned C-shared library builds with Go 1.25.9. Existing real-process
`directed_packets` and `idle_dm_presence` regressions pass with the new library:
packet/stream callbacks coexist, offline advertisements retain bounded retries,
and delivery reconnects after the other installation returns. Platform CI and
the configured Windows installer are checked separately on the committed head.
