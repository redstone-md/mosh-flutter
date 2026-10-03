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
