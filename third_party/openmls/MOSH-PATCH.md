# OpenMLS 0.8.1 historical lifetime validation

Vendored from the crates.io `openmls` 0.8.1 archive, upstream commit
`47dbedecad0c1fd8eb5368d582250ebfcc1e1ce6`, directory `openmls/`.
The original MIT license is copied from that commit. Registry cache markers
are omitted. The distributed manifest and source metadata are retained.
Archive SHA-256: `dcb512bfe6a55777518853ea535c6241f069cb0e8984678c117151d2a1e7e903`.

The only source change is `src/key_packages/lifetime.rs`, recorded in
[`openmls-historical-validation.patch`](../../docs/Proposals/openmls-historical-validation.patch).
`Lifetime::with_validation_time` scopes synchronous lifetime checks to an
authenticated historical Unix timestamp on the calling thread. A guard
restores the previous policy on return or unwind, including nested calls.
Creation and signature checks retain upstream behavior. The application uses
the unchanged `has_acceptable_range` predicate to enforce lifetime limits.

Mosh selects this policy only for signed, authorized retained DM admission
evidence for its own next MLS epoch. Ordinary admission uses the current clock.
See [ADR 0032](../../docs/ADR/0032-dm-offline-recovery.md).

Upstream files are exempt from Mosh's file/type/function size limits. Keep
them unchanged on upgrades, reapply this patch and run the focused policy and
signed recovery tests plus the normal core checks. Remove the patch when an
upstream existing-group API supports authenticated historical validation.
