# Historical MLS validation: pending approval

Issue 26's retained commits can outlive a joining client's KeyPackage. OpenMLS
0.8.1 checks the current clock both when validating that package and when
processing the Add commit. Its default lifetime is 84 days. Its existing-group
API offers no historical validation time. Removing package validation alone
does not restore a missed transition.

The [prepared patch](openmls-historical-validation.patch) proposes a scoped,
thread-local lifetime validation clock. It restores the prior policy on return
or panic, including nested calls. It does not change the process-global clock,
skip signatures, relax lifetime ranges or import another client's MLS state.
The patch is unapplied and has not been tested against the OpenMLS crate yet.
Project dependencies remain unchanged.

If approved, vendor the existing OpenMLS version with this small documented
patch. Bind the original admission time into the author-signed recovery
evidence and use it only after verifying the original author, same group and
exact next epoch. Normal admission continues using the actual clock. Verify
genuine expired packages and commits, invalid historical times, forged evidence,
ordering, clock restoration and continued independently keyed messaging.

Approval is required by root `AGENTS.md` before changing dependencies. The
approved issue-26 plan explicitly excluded dependency changes. The alternative
is to accept and document the expiry limit; it would leave long-offline epoch
recovery incomplete. Retained semantic text and recovery evidence cannot remove
this library restriction by themselves.
