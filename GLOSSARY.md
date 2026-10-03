# Mosh domain terms

## Send admission

Acceptance of a new text for delivery after its message and provisional
attempt are saved atomically. Refused admission is Failed and requires a
deliberate retry. Accepted admission can become Queued while later state
writes wait for storage recovery. See ADR 0037.
