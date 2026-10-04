# ADR 0039: personal and shared chat names

Status: accepted for issue #47.

## Behavior

DMs and channels have personal display names. Only the user's active linked
installations exchange these names; reset stores a versioned tombstone. Channel
addresses and DM session identities do not change. Groups have one shared name,
which only current admins may change. Names contain 1–64 Unicode scalar values
after trimming and reject controls and line separators.

This follows established messaging conventions: Signal separates [personal
nicknames](https://support.signal.org/hc/en-us/articles/360007319011-Manage-Contacts-Nicknames-and-Notes)
from [shared group information and its history alerts](https://support.signal.org/hc/en-us/articles/360050427692-Manage-a-group).
The user chose personal channel names and admin-only shared group names.

## Ownership and persistence

`ChatNames` owns an account-scoped encrypted register in the additive `chat_names`
table. Lamport counters and stable writer ids establish a total order. Reset
records remain in the register, so an offline stale replica cannot resurrect a
name. The existing device-link runtime is the sole owner of stream 3 and its
inbox. It exchanges pages of at most 16 records through Moss's encrypted directed
stream, pinned to the recipient's trusted roster peer id. Signatures bind the
account, sender, recipient, exact roster digest and payload. Removed devices and
foreign accounts cannot read incoming packets or author writes. Linking an
installation rebinds the register to the adopted account; old-account names do
not migrate. Unknown channel names remain stored without joining a channel.

A newly linked installation rejects personal-name writes until it durably
imports every page of an initial register pull. The encrypted register retains
that readiness across restart, including an empty initial pull. The imported
Lamport clock then orders its first rename after the received names. Existing
registers without the readiness field need one initial pull when other devices
are linked. A sole installation can write immediately. Later offline writes
remain available and concurrent edits use the existing total order.

Matching durable-save digests stop periodic full-register pulls. A local write
changes the digest and starts another pull. A first-page response also
advertises the responder's durable digest using the existing Saved message.
The initiator learns the responder's state without requiring a reciprocal
pull; a differing digest resumes synchronization. This allows either device
to deliver an edit without continually transferring all names or causing a
request loop after restart. A saved digest alone cannot complete initial
synchronization.

A group's restoring record contains the shared-name certificate, pending status
and rollback state. Accepting a name saves the record, MLS snapshot and typed
history event in one encrypted transaction. No UI success precedes that commit.
`GroupNameChanged` is a system event, localized when rendered, with the original
author retained across forwarding and restart.

## Group synchronization and authority

Name request/state/ack frames use an MLS exporter-derived epoch key with
AES-256-GCM and a fresh random 96-bit nonce, plus SenderProof. The exporter label
is `mosh-group-chat-names-v1`; the group id is its context and AEAD associated
data. The signed outer frame binds the epoch and operation. This does not advance
normal application-message ratchets: old clients and offline members can skip
unbounded metadata rounds without exceeding OpenMLS's forward-distance limit.
The live MLS tree authorizes the carrier's membership. Shared state additionally
requires the current plain-group admin or verified org roster admin *before*
decryption. A saved origin certificate retains the original MLS author and
context; a current admin can forward an established name after that author's
departure. Versions order epoch, roster version, Lamport counter and full signer
id. Updated admins converge on the same maximum version.

Offline names remain pending and retry through the existing group service.
Publication is insufficient: an authenticated peer acknowledges only after
saving the state. Pending clears when another updated participant saves the
current revision; it does not claim that every offline participant received it.
Replacing a pending rename marks its earlier event as superseded. An
acknowledgement settles only the event for that exact revision.
Periodic requests recover current state for new and returning participants.
Compatible resync requests recover missing membership commits before attempting
new-epoch metadata. A departing admin includes an optional signed, MLS-encrypted
name state inside the existing SelfRemove envelope, so the successor learns the
last name before removing the author. Invalid optional state cannot block a
valid departure. A valid state's persistence failure prevents removal until
the state can be saved on redelivery. If admin rights disappear before
acknowledgement, pending
changes roll back and their local history events show rejection.

## UI and compatibility

One dialog serves the existing chat menu and the list row's secondary-click or
long-press menu. It preserves input on failure, validates without truncation,
prevents duplicate submissions, and has a separate personal-name reset action.
Riverpod owns native names; the foreground poller refreshes them. The personal
name resolver is shared by list/search, header/details and call dialogs. Details
retain the original identity or channel address.

The table and persisted fields are additive. Existing clients ignore the optional
SelfRemove field and unknown metadata frames and continue ordinary messaging.
They neither update names nor acknowledge their persistence. No MLS capability
or required extension changes: custom context extensions would require migrating
existing leaves and would break that compatibility choice.

## Checks and boundaries

Tests use public runtime methods with real encrypted storage, independent native
processes for linked-device paging/conflicts/reset/revocation, real MLS frames
for group recovery and succession, and test/support for Flutter interactions.
The existing process-worker ownership exception in ADR 0029 also covers names
commands; no second inbox consumer is introduced. Generated bindings retain their established source-budget exception.
The existing `create_group` and `send_attachment` constructors retain their
previous function lengths; their only additions initialize the optional name
fields. New feature functions and test scenarios fit the 50-line budget.

Recovery requires a reachable updated admin or an admin's retained departure
state. All copies lost with their encrypted stores cannot be reconstructed.
Delivery of an offline departure follows the existing group leave semantics;
this change does not introduce a membership departure journal.
