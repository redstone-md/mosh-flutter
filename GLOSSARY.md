# Mosh domain terms

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
