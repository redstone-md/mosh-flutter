# Historical MLS validation

Issue 26's retained commits can outlive a joining client's KeyPackage. OpenMLS
0.8.1 checks the current clock both when validating that package and when
processing the Add commit. Its default lifetime is 84 days. Its existing-group
API offers no historical validation time. Removing package validation alone
does not restore a missed transition.

The [patch](openmls-historical-validation.patch) adds a scoped,
thread-local lifetime validation clock. It restores the prior policy on return
or panic, including nested calls. It does not change the process-global clock,
skip signatures or import another client's MLS state. The user approved the
dependency change on 2026-09-28. The existing version is vendored under
`third_party/openmls`, with its license and provenance. Core and probe use that
same copy without changing dependency versions.

The original admission time is part of the author's v2 evidence signature.
Recovery verifies the original author, roster, same local group and exact next
epoch before selecting that time. Zero times and times over one hour ahead of
the local clock are refused. Package/leaf signatures and historical validity
windows still pass normal OpenMLS checks. The shared package decoder also
enforces OpenMLS's maximum acceptable lifetime range, 84 days plus one hour.
OpenMLS exposes that predicate but requires the application to apply it.
Normal admission continues using the actual clock. Older evidence without a
signed timestamp retains its v1 signature and uses the actual clock; it cannot
establish an authenticated time after its package expires.

`mosh-core/tests/historical_lifetime.rs` verifies the public patched API at
strict validity boundaries, nested calls, thread isolation and panic cleanup.
The signed recovery test creates a genuine package/commit valid 100 days ago.
It first failed on OpenMLS's current-clock check, then passed historical replay,
restart and independently keyed messages in both directions. It also refuses
altered time, invalid validity boundaries, future time, tampered package/commit
signatures and an excessive lifetime range. Full core checks and independent
Standards/Spec review are recorded in the issue-26 plan.
