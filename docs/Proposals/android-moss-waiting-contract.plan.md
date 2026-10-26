# Moss waiting contract for IVO-136

Status: proposal for upstream maintainer review, not an implemented capability.
No Moss files or consumer repositories are modified by this document.

Mosh enables waiting after setup and automatically selects economical waiting
when no interactive work, accepted call or user-started transfer needs active
transport. Application integration is explicit opt-in; Mosh users do not need
to discover an extra setting. Existing Moss consumers keep their defaults.

## Proposed additive C ABI

`int32_t Moss_SetActivityMode(MossHandle handle, int32_t mode)`

- Mode `0` = ordinary active behavior; `1` = economical waiting.
- Only explicit callers use the new lifecycle. Initialization and Start retain
  their existing behavior. Invalid modes/handles fail without partial mutation.
- Success accepts the desired mode; it does not claim a relay is reachable.
  Transition work is asynchronous, bounded and idempotent. Serialize changes
  against Stop; Stop remains destructive and is never used for mode switching.
- Extend `Moss_GetMeshInfo` JSON additively with `activity_mode` (actual mode),
  `requested_activity_mode`, `waiting_reachability` (attaching/ready/unavailable),
  and `waiting_attachment_count`. Event callbacks announce transitions using
  the existing event envelope; exact error/event enum allocation is upstream's
  responsibility and must be recorded before implementation.
- An older library with no symbol is reported as unsupported; Mosh does not
  silently label a full active mesh as economical waiting.

## Lifecycle invariants

Preserve the node identity, UDP transport handle, callbacks, room subscriptions,
authenticated sessions, stream registrations and application-owned persistence.
Retain one live relay attachment, with a second connection permitted only during
bounded handover. Do not act as relay/supernode for third-party traffic in waiting.
An authenticated relay carrier remains available for the installation's traffic.

Suspend ordinary tracker announcements, broad DHT/LAN discovery, overlay fanout,
peer warming and unrelated maintenance/dialing while waiting. Keep only work
needed to maintain/recover the selected attachment and transport liveness.
Do not retain the full direct mesh behind the waiting label. Preserve current
conversation authentication while migrating transport; if the current protocol
cannot safely retain it, fail the transition visibly instead of claiming success.

Without an attachment, perform bounded discovery against already-known relay
candidates. Use one in-flight attachment attempt and exponential backoff with
jitter: 5s initial, maximum 5min. Network changes trigger one immediate attempt,
not an unbounded parallel retry. A successful attachment resets the backoff.
Do not busy-loop when Android withholds network access.

Active mode restores ordinary discovery and maintenance once per transition.
Incoming authenticated user work may temporarily require active transport;
untrusted hints alone cannot create unrestricted fanout or media capture.
Keepalive cadence must meet the existing carrier timeout; changing that wire
behavior or relay defaults is a separate upstream decision, not a battery guess.

## Wake signals and abuse

Prefer existing authenticated conversation packets over inventing a second wake
protocol. If a separate hint is actually required, propose its exact authenticated
envelope, target binding, nonce/expiry, replay cache and per-source/global work
limits before implementing it. No arbitrary wake payload is treated as a message,
receipt or call acceptance. No relay stores chat history or bypasses OS sleep.

## Acceptance and authority

Upstream must verify two independent leaves and a real relay: messages both ways
through active→waiting→active, handover/reconnection, offline relay, duplicate
mode requests and concurrent Stop. Verify preserved identity/room/callback state,
bounded attachments/retries and unchanged ordinary-consumer behavior.
Run the relevant Bastion/gaming compatibility scope through their maintainers;
do not edit those repositories from Mosh.

Mosh integrates only a reviewed upstream commit, then exercises the existing
real-process bridge scenario. Physical Android measures actual wakeups/radio,
traffic and delivery latency; this API proposal does not establish battery goals.

Required owner action: approve this proposed public contract and coordinate the
upstream Moss implementation with its maintainer. Repository rules prohibit
editing the submodule or sibling repositories as part of this Mosh change.
