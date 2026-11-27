# ADR 0005: Roster-derived commit authority in org groups

## Status

Accepted

## Context

Private groups accept commits only from a pinned `current_admin_fingerprint`,
transferred via `AdminHandoff` on graceful leave. In an org group this
deadlocks revocation of the group admin themselves: nobody else may commit
the Remove, and a hostile or offline admin never hands off. Serverless
operation rules out any external arbiter.

## Decision

Org groups abandon the single group-admin mechanism entirely. A commit is
valid iff its author's peer-id (from the leaf credential, ADR 0004) carries
`role: admin` in the verifier's current verified roster. Commits carry the
author's roster version; a commit from an unknown admin with a newer roster
version is buffered pending roster arrival (shared machinery with epoch
resync buffering). Only an author that already holds a leaf in the group is
buffered, with a per-sender cap, and a full buffer evicts from the sender
holding the most entries, so neither outsiders nor flooding members can
evict a real admin's commit. Creating an org group requires ≥1 admin in the initial
set (UI-enforced, soft).

## Consequences

- Revoking any member, including a group's only acting admin, is always
  possible while at least one other org admin exists.
- Concurrent commits from two live admins can fork the MLS tree (gossip has
  no total order). Removals and admissions therefore have one designated
  committer: the roster admin with the lowest peer-id among those holding a
  leaf, the member being removed or admitted excluded, so a rejoining admin
  never ranks for its own admission. The designated admin admits a joiner as
  soon as its KeyPackage arrives. An admin of rank k commits only after k ×
  15 s, and only if the change is still undone in its tree: the leaf is
  still there, or the joiner's KeyPackage has no leaf yet (a rejoiner's
  stale leaf has another signer, so it does not count). It stands in for
  offline admins without racing online ones. Waiting admissions are held in
  memory; a joiner re-sends its KeyPackage until a Welcome arrives, and a
  re-send keeps the waiting admin's deadline.
- A fork that still happens is detected when a commit arrives for one of
  the last few epochs this session merged, with other bytes. It counts only
  if it stages against the state kept for that epoch and its signing leaf
  is a roster admin. Both branches keep the commit with the lower SHA-256;
  a client that merged the other reports `needs_rejoin` and stops acting as
  an admin. That verdict is saved in the group's session record, so it
  survives a restart; rejoining starts a new record without it. The kept
  epochs themselves are in memory, so a rival that arrives after a restart
  goes unnoticed.
- A group whose last in-group admin is revoked becomes crypto-unmanageable;
  backstop is re-creating the group from the roster (one action).
- `AdminHandoff` remains for non-org groups only.
