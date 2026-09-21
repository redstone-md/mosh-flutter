# Ubiquitous Language

Glossary of domain terms. Definitions only — no implementation details.

## Organization (org)

A signed membership document (roster), not a server or infrastructure. An
org's identity **is** its root public key.

## Org root key

Ed25519 keypair held exclusively by the org admin's tooling. Signs rosters.
Its public half is the org's identity and trust anchor.

## Roster

The canonical, versioned, org-root-signed document listing current members.
Membership in the org is defined as presence in the latest verified roster —
nothing else grants or preserves membership.

## Member

A person in an org, identified by their **moss peer-id**. In any org context
the peer-id is the sole durable identity anchor, at every layer including
the crypto layer.

## Moss peer-id

Stable per-installation identity from the moss node, persisted across
restarts. Durable. Sender authenticity against it is proven by the org
signed envelope — the gossip transport itself does not authenticate
senders; only the relay path pins it.

## MLS fingerprint

Derived from a per-conversation MLS signature key. Ephemeral relative to a
person: differs per conversation, not usable as a durable member identifier.
Contrast: [[moss peer-id]].

## Org admin

A member whose roster entry carries `role: admin`. In org groups, authority
to change group membership derives from this roster role. Distinct concept
from [[Group admin]].

## Confirmation code

The first 12 hex characters of a joining member's [[moss peer-id]], shown to
them at join time and relayed to the org admin out-of-band. Proof that a
pending join request belongs to a known person. Approval is impossible
without it. (Not a "short hash for disambiguation" — that meaning is dead.)

## Conversation

A place where people exchange messages: a message list, a composer,
attachments, delivery status, and a way to leave. Mosh has three kinds — a
DM between two people, a channel, and an [[Org group]] — and each one is the
same conversation with its own membership and authority rules on top.

## Org group

A [[Conversation]] bound to an [[organization]] at creation (the binding is
the org's identity). The binding — not membership overlap — is what makes a
group "organizational": it activates roster-derived authority and
revocation enforcement. A group without a binding is a plain private group;
no org ever touches it. Org groups are created deliberately by members
(ad-hoc); the org does not auto-create or auto-populate groups.

## Group admin

The single per-group authority in **non-org** private groups (a
[[Conversation]] with no org binding), tracked by MLS fingerprint and
transferred by handoff. Does not exist in org groups — org groups derive
authority from the roster instead.

## Read receipt

A counterpart's MLS-authenticated notice that the user opened the
conversation — rendered as the existing delivery ticks changing color,
never as a third tick. Off by default and symmetric: a user who does not
send receipts does not see others'. DM only; channels never carry it.
_Avoid_: read tick, "delivered" (that term is taken by [[Delivery]])

## Delivery

The runtime-level fact that a message's frame reached the counterpart's
runtime (MLS-encrypted ack, two ticks). Says nothing about the user having
seen anything. Distinct from [[Read receipt]].

## Typing indicator

A live "the counterpart is typing" signal (emit-on-input, ~3s refresh, 5s
expiry), MLS-encrypted so a mesh bystander cannot forge it. DM and groups;
channels never carry it.
_Avoid_: typing status, composing
