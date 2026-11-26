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
buffered, with a per-sender cap, so outsiders cannot evict a real admin's
commit. Creating an org group requires ≥1 admin in the initial
set (UI-enforced, soft).

## Consequences

- Revoking any member, including a group's only acting admin, is always
  possible while at least one other org admin exists.
- Concurrent commits from two live admins can fork the MLS tree (gossip has
  no total order). Removals therefore have one designated committer: the
  roster admin with the lowest peer-id among those holding a leaf, the
  member being removed excluded. An admin of rank k commits only after k ×
  15 s and only if the leaf is still in its tree, so it stands in for
  offline admins without racing online ones.
- A fork that still happens is detected when an admin's commit arrives for
  an epoch already merged with other bytes (the commit log holds ours).
  Both branches keep the commit with the lower SHA-256; a client that merged
  the other reports `needs_rejoin` and stops acting as an admin. Admissions
  are still committed by every admin that sees the KeyPackage and rely on
  this detection alone.
- A group whose last in-group admin is revoked becomes crypto-unmanageable;
  backstop is re-creating the group from the roster (one action).
- `AdminHandoff` remains for non-org groups only.
