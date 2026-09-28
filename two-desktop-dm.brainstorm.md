# Two-desktop DM, issue 24

## Problem and scope

Pairing already creates one signed user roster with independent device keys.
The DM runtime still assumes two installations. Its MLS adapter already has
the required Add, Commit, Welcome and independent storage operations.

Deliver one existing text DM on two linked desktops and one counterpart.
Keep the current bridge, conversation id, invite address, fingerprint and UI.
Exclude history import, offline catchup, revocation, groups, attachments,
calls, mobile delivery, subscriptions and wallets.

## Options

1. Copy the original MLS state. Reject this. Sender ratchets and private keys
   would be shared and simultaneous sends would reuse secrets.
2. Forward through the original installation. Reject this. The linked device
   must work while that installation is off.
3. Add an independently authorized MLS leaf to the existing conversation.
   Choose this. OpenMLS already supports it and Moss already has directed,
   encrypted streams, including relay delivery.

## Chosen direction

- Bind a device's public MLS signer to its signed user roster through an
  MLS-encrypted identity announcement. Pin the counterpart's user id through
  the existing two-member DM, then accept only verified roster extensions.
- Send offers and signed KeyPackages privately between linked installations.
  A new client creates its own keys and retains them before requesting Add.
- Send the authorization, Commit and Welcome privately. Validate admission
  before applying a Commit, and check the resulting leaf set. Persist each
  transition atomically with its delivery journal. Retry identical admissions
  and acknowledge durable application, including after restart.
- Reuse the existing framed Moss stream for live ciphertext fan-out to
  admitted devices. Device metadata never enters public gossip.
- Authenticate text ids and author metadata before deduplication. Display all
  own-device messages as the existing local author and all counterpart-device
  messages as the same contact. A sibling receipt cannot mean delivery to the
  counterpart. Keep the fingerprint read-only.
- Extend the encrypted session record compatibly. Add no tables, dependency,
  or Dart bridge method. Existing two-party clients retain the old path.

## Risks and boundaries

Admission is a durable epoch transition, not a best-effort send. Serialize
admissions in this slice; do not design concurrent roster merging. A client
missing a later epoch while offline will need issue 26. Already received
history is not imported in issue 24. DM participants can observe that two
devices belong to the same user. Network traffic anonymity is not promised.

## Test boundary

Issue 24 explicitly requires three independent installations using real Moss
and OpenMLS. Use the public DM runtime and existing independent-process test
runner, plus the public bridge for a discovery scenario. Observe session lists,
message ids, authors, delivery state and persistence through public snapshots.
Use no new transport or storage doubles. Validate the current Flutter shell
against the unchanged bridge and preserve its existing tests.
