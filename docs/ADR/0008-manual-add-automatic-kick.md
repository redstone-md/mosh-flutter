# ADR 0008: Manual batched Add, automatic kick

## Status

Accepted

## Context

Org groups are ad-hoc (created by members from the roster); the org never
auto-creates or auto-populates groups. With multiple org admins, any
automatic MLS commit reaction to roster changes turns the concurrent-commit
fork risk (ADR 0005) from a rarity into a steady background condition —
several online admin clients would race to commit the same Add. Yet
revocation speed directly bounds how long a revoked member keeps reading
group traffic.

## Decision

Adds and kicks are asymmetric. Adding members is manual: the admin client
shows "roster has +N not in group G — add?" and one click issues a single
multi-proposal commit (N × Add). Kicking is automatic: on `member_removed`,
the designated admin client (ADR 0005) commits the Remove for every group
bound to that org, with no user interaction; the other admins stand by
and commit after their delay only if it has not landed.

## Consequences

- Group composition stays a social decision (not every org member belongs
  in every group), and human click speed naturally serializes concurrent
  admins during onboarding waves.
- Revocation does not wait for a human; the window is bounded by admin
  client uptime, not attention. Runbook recommends ≥2 admins.
- A kick waits at most one fallback delay per admin ranked above the one
  that commits it. Admins whose rosters or trees disagree can still both
  kick; the fork rule from ADR 0005 sends one branch to rejoin.
- A default `#general` is just the first ad-hoc group created at org setup;
  no special mechanics to maintain.
