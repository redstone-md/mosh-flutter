# ADR 0023: the tree says who the admin is

## Status

Accepted.

## Context

A private group has one admin, held as `current_admin_fingerprint` on every
member's session. Everything that moves membership is gated on it: admissions,
removals, serving a resync replay.

When the admin left, `close()` published two frames — a Commit that dropped the
admin's own MLS leaf, and an `AdminHandoff` naming the successor. The Commit
travelled the reliable path (`CommitSequencer` orders by epoch, buffers
out-of-order arrivals, asks for a replay on a gap). `AdminHandoff` travelled
best-effort past all of it, and it was the only thing that moved
`current_admin_fingerprint`. One dropped frame and every member kept pointing at
someone who had left — a group frozen for joins and removals, permanently.

Underneath that, the departure never happened at all. The Commit came from
`MlsSessionCrypto::remove_self_commit`, which asks OpenMLS to commit the removal
of its own leaf. OpenMLS refuses that at creation time
(`CreateCommitError::CannotRemoveSelf`), so `close()` returned an error at the
first `?`: no Commit, no `AdminHandoff`, and the local session not even
released. An admin with at least one other member could not leave. It went
unnoticed because a solo admin has no successor and skips the branch entirely.

The successor was already chosen by a rule, not by a negotiation: `min()` over
the remaining member fingerprints. A rule both sides can run does not need a
frame to carry its answer.

## Decision

**Leaving is a proposal, for everyone.** MLS does not let a member commit its
own removal, so a departing member publishes a self-removal proposal and a
member who stays commits it. That was already the path for ordinary members.
The admin now takes the same one.

**Who commits is the same `min()`.** An ordinary member's departure is committed
by the admin. The admin's own is committed by the successor — the lowest
remaining fingerprint — so exactly one member acts, and the tree that results
names that same member.

**The committer re-issues the removal inline.** The proposal is used as proof
only: it must be a Remove naming the leaf that signed it, so it can never be
turned into "have someone else kicked". The commit then carries its own Remove
by value rather than a `ProposalRef`, so a member that never received the
proposal can still merge it. `commit_to_pending_proposals` could not do that,
and a commit that depends on a second best-effort frame reaching everyone would
have rebuilt this bug one level down — a resync replay of it would fail for
exactly the members who most needed the replay. `replace_member` already had to
learn this.

**Every member derives the admin from the MLS tree.** After any control frame,
`reconcile_admin` looks at the tree: while the admin holds a leaf, nothing
changes; once the leaf is gone, the lowest remaining fingerprint takes over.
Direct delivery, a commit drained out of the sequencer's buffer, and
`absorb_resync_commits` therefore all end at the same admin, and so does a
restart, because the tree is what is persisted. Nothing has to be replayed for
the group to agree.

**`AdminHandoff` is no longer read.** A second writer of the admin pointer can
only disagree with the tree, and it did: arriving before the commit, it moved
the pointer, and the commit was then dropped by the author check below. It is
still *published* when an admin leaves, because clients released before this
ADR cannot derive anything and still need to be told.

**Plain-group commit authority is MLS and the sequencer.** The
`from_fingerprint == current_admin_fingerprint` check is gone. On a plain group
the control channel is unauthenticated (the signed envelope is org-only, ADR
0007), so that field is a self-claim anyone can copy: the check stopped no
attacker. What it did stop was a member whose admin pointer was stale — it
dropped the commit that would have corrected it, without even registering a gap,
which is the freeze this ADR is about. It would also drop the successor's
departure commit, which is authored by a non-admin by design. A forged commit
still fails `process_commit`, and the sequencer confirms only after a successful
apply, so garbage never poisons delivery — the property `commit_sequencer`
already documents.

Org groups are untouched: authority there is the signed roster (ADR 0005), the
fingerprint machinery is not consulted, and `reconcile_admin` returns early.

## Consequences

- An admin can leave. Before this, it could not.
- Losing the `AdminHandoff` frame costs nothing. Losing the Commit costs a
  round trip: the next commit is a future epoch, so it buffers, the gap fires a
  resync request, and the replay brings the member to the same admin.
- A departure still needs one frame to reach one member — the proposal, to
  whoever must commit it. If it is lost, the leaver keeps a leaf and the admin
  pointer does not move. That is the same exposure every ordinary member's
  leave already had, and the group is not frozen: the leaver is gone, so it is
  the successor who must retry by leaving again. Detecting a departed member
  who never announced itself is liveness detection, and no group frame carries
  liveness today.
- A member of a plain group can now author a membership commit that others
  apply. In honest operation none does — only the admin and the successor
  commit — and a malicious member could already do this by copying the admin's
  fingerprint into its own frame. What changed is that the group no longer
  splits when one does: previously some members applied such a commit and the
  admin never did.
- `remove_self_commit`, `queue_remote_proposal` and `commit_pending` are gone,
  replaced by `commit_departure`. There is no other caller: a proposal is
  stored only to be committed, and only a departure is proposed.
