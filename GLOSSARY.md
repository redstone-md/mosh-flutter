# Mosh domain terms

## Mosh+

**Mosh+ entitlement**:
A time-limited benefit belonging to a Mosh account. Its owner may choose to
display a verified badge to other users.
_Avoid_: paid wallet, premium device.

**PLUS payment order**:
An individual quote connecting a specified token amount, recipient and payment
reference to one entitlement purchase.
_Avoid_: recurring subscription, entitlement certificate.

**PLUS certificate**:
An issuer-signed statement that a particular Mosh account holds Mosh+ until a
specified expiry. It does not identify the paying wallet.
_Avoid_: account ownership proof, payment receipt.

**PLUS visibility**:
The account owner's choice to disclose their valid Mosh+ status to other people.
_Avoid_: per-chat subscription, deletion of previously disclosed proof.

**PLUS paid interval**:
An immutable start and expiry authorized by one verified purchase. A future
interval becomes active at its start; renewal preserves earlier paid time.
_Avoid_: floating expiry, wallet balance.

**PLUS renewal series**:
An anonymous billing capability shared by linked devices to serialize purchases.
Recovery can join scheduling authority without granting access to other orders.
_Avoid_: account ID, public wallet identity.

**PLUS wallet recovery**:
Wallet-authorized issuance of its own original paid intervals to a new account.
It does not restore the old account, keys or chat history. One additional issuance
per paid order is available; genuine old certificates retain their original expiry.
_Avoid_: account recovery, instant revocation.

## Send admission

Acceptance of a new text for delivery after its message and provisional
attempt are saved atomically. Refused admission is Failed and requires a
deliberate retry. Accepted admission can become Queued while later state
writes wait for storage recovery. See ADR 0037.

## Saved network choice

Persisted VPN-bypass consent naming a physical adapter, or automatic routing
when unset. It differs from the running node's binding. Applying a changed
choice requires a process restart; saving setup completion precedes restart.

## Conversation attachment

An attachment descriptor interpreted with its observed transfer state and
message ownership. Message cards, the file index and open actions share its
readiness, progress and allowed controls. A failed or cancelled transfer is
not ready merely because a cached local path remains.

## App access

**Mosh app lock**:
User authentication protecting access to the chat interface while background
message reception and incoming calls remain available. Accepting a call does
not unlock access to the chats.
_Avoid_: going offline, ending a call, locking all background reception.

**Mosh wake signal**:
A short-lived hint that an installation may have pending Mosh activity. It is
not itself a delivered message or an accepted call.
_Avoid_: delivery receipt, call acceptance.

**Mosh waiting mode**:
A background availability state in which an installation waits for incoming
Mosh activity. It differs from an ongoing call and deliberately going offline.
_Avoid_: active call, offline mode.

**Mosh notification preview**:
User-authorized display of a sender or caller name, or message text, outside
the chat interface. Allowing a preview does not unlock access to the chats.
_Avoid_: unlocking Mosh, message read receipt.

## Calls

**Mosh call**:
A live conversation between the two users of a private DM, with one participating
device per user. Each participant independently chooses whether to send audio
and video.
_Avoid_: video session, separate audio conversation.

**Participating call device**:
The device selected to carry a user's live audio and video in a Mosh call.
Other linked devices may ring without becoming participants in that call.
_Avoid_: call participant when referring to an installation rather than a person.

**Call refusal**:
A user's decision to reject a pending Mosh call across their linked devices.
The caller must confirm it before an answer wins. A nonparticipating device's
stale refusal cannot end an accepted call. It differs from silencing an alert
or missing a call.
_Avoid_: dismiss notification, missed call.

**Call occupancy**:
A Mosh user's reserved participation in one pending or ongoing call across
their linked devices. Another call cannot be admitted while that reservation
is known to remain in effect; disconnected devices can temporarily hold
different reservations.
_Avoid_: microphone busy, device busy.

**Call occupancy conflict**:
Knowledge that a user's linked devices hold different calls after operating
without each other's state. Existing calls continue, the user sees the conflict
and new admission stays blocked until all calls involved have ended.
_Avoid_: call waiting, automatic call transfer.
