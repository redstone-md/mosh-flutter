# ADR 0038: authenticated group senders and DM offers

Accepted 2026-10-04. This changes the group application protocol, org-carried DM
offers and targeted DM admission. Flutter function arguments, database tables
and dependencies stay the same.

A group member could encrypt a valid MLS message while claiming another
installation's Moss ID in text, typing or an attachment. Comparing two claimed
attachment IDs did not prove either ID. Plain group DM offers required no MLS
membership. An offer could also advertise somebody else's DM key, and a member
who learned its invitation could race the intended recipient's unsigned first
KeyPackage.

## Shared sender proof

`sender_auth::SenderProof` signs one versioned transcript with the existing Moss
Ed25519 key and the conversation's full MLS signing key. It includes the full
MLS key and encoded application frame. The existing length-prefixed signature
context scopes both signatures to the organization, mesh and exact channel.
The new proof encodes its signed payload as base64 so nested org envelopes remain
below Moss's 64 KiB publication limit. Existing org envelope encoding is unchanged.
Moss identity capture uses the existing load/save callbacks during serialized
native initialization. The node verifies the captured public key against its
actual transport identity. Private keys never cross the bridge or enter logs.
Initialization fails if that signer is missing or cannot be verified.

Group text, attachment manifests, typing and DM offers use this proof. Incoming
frames must prove possession of both keys and current MLS membership before
application parsing or decryption. Org groups also require the MLS credential to
equal the proven Moss ID and the current roster to authorize it. Claimed author
IDs must equal the proven Moss ID. Display names remain user-chosen labels.

OpenMLS still authenticates the actual ciphertext sender. Decryption runs on a
restored candidate and commits it only when its full sender key matches the
proof. Rewrapping another member's ciphertext therefore cannot consume that
member's legitimate message. Typing bodies must parse and match their signed
name. Attachment author fields must match the proof. DM offer bodies are MLS
encrypted before the shared sender proof covers the control frame.

Group Welcome also verifies the actual MLS author against the advertised admin
fingerprint before accepting its tree. Org Welcome additionally requires the
author's credential to equal the verified org envelope sender. Both stage on a
copy so a substituted Welcome cannot consume a genuine join's KeyPackage.

## Invitations bind both endpoints

Native DM creation signs the canonical invitation URI with the creator's Moss
and DM MLS keys. The proof covers routing fields and the advertised DM
fingerprint. Duplicate proof or target fields are rejected. A group offer must
prove that its DM creator is the authenticated offering member.

`PrivateDmRuntime::authenticated_owned_invite` binds an unadmitted creator's
invitation to one recipient Moss ID and saves it in the existing invitation
record before publishing the offer. Persistence refusal restores the earlier
in-memory invitation and prevents publication. An already targeted invitation
cannot be retargeted. The group action acquires the DM owner before the group
owner, with no overlapping locks.

The recipient checks that the invitation targets its real Moss identity. Its
first KeyPackage carries the same dual signature, scoped to DM admission. The
creator verifies the durable target, proven Moss identity and the full signing
key of the validated KeyPackage before changing peer metadata or MLS membership.
Raw KeyPackages cannot downgrade targeted admission. Retransmission and pending
join recovery retain the authenticated payload and original MLS private material.

Org-carried DM offers use the same owned, targeted invitation. Outgoing offers
require both endpoints in the roster. Incoming offers verify ownership before
deduplication, and acceptance verifies again, including restored pending offers.
An old pending offer without these proofs must be dismissed and reissued.
Acceptance rechecks both endpoints against the current verified roster, including
roster updates queued since delivery. Revocation does not close established DMs.
Org offer URIs remain visible to topic readers; the pinned target prevents another
reader from taking admission.

The recipient stages Welcome on a copy of its provider and verifies its actual
MLS author against the advertised fingerprint and, when present, the full owner
proof key. Rejection preserves the original KeyPackage so the genuine Welcome
can still succeed. Names come from the verified MLS credential.

## Compatibility and recovery

This is a coordinated group protocol upgrade. There is no fallback for unsigned
group application frames, including legacy plaintext offers. Group membership
controls retain their existing protocol. Manual DM invitations without a target
retain legacy admission for the invitation holder; they do not promise a
particular recipient identity. Invitations with a proof always verify it.
Existing DM sessions and linked-device workflows remain readable and usable.
Org offer records persist before publication. If subsequent local linking fails,
the published invitation remains usable. The conversation UI owns cleanup of a
newly created DM whose offer failed; the group bridge retains caller-owned invites.

First sends and deliberate group retries share text encoding. A retry encrypts
the trusted local message again in the current epoch, preserving its message ID
and timestamp. It saves the advanced MLS snapshot before publication. This
upgrades old stored frames and handles restart after a snapshot refusal without
reusing a sender generation. Existing encrypted history is readable, but cannot
gain retrospective sender verification. Public channel author labels are
outside this authenticated group boundary.

Regression tests exercise spoofed authors, changed signed headers, transplanted
ciphertext, cross-channel replay, malformed typing, outsider offers, invitation
ownership and target races. Controls cover real Moss identities and OpenMLS,
roster revocation, genuine Welcome after rejection, retransmission, pending
recovery, restart and storage refusal. Native multi-installation tests keep the
existing independent-process policy. Single-process identity tests deliberately
disable the process-global keystore when creating independent ephemeral nodes.

New production modules stay below 400 lines. Existing runtime/session type and
constructor exceptions from ADRs 0019 and 0026 remain. Security scenario tests
may exceed 50 lines because setup, attack and legitimate control are kept in the
same test; they do not add production exceptions.
