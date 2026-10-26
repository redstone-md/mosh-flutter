# Moss waiting contract for IVO-136

Status: the owner-approved upstream implementation is complete in separate
[Moss PR #31](https://github.com/redstone-md/moss/pull/31), without merging it.
Mosh's integration candidate pins `fd6d7d7916aa73c3f6b7079baba0d500a30d260e`
after its eight CI jobs passed, including Linux/Windows, race and repeated soak.
Mosh integration checks, upstream maintainer acceptance and physical Android
acceptance remain required. This is not a shipped capability. Moss source edits
remain confined to its separate worktree and PR; the downstream gitlink records
the exact dependency under review.

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

The isolated implementation in [Moss PR #31](https://github.com/redstone-md/moss/pull/31)
uses error -15 for an invalid mode and event 12 on the pinned base. These
allocations require rechecking against divergent upstream branches before landing.

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

The owner explicitly granted the repository-boundary exception for this work.
The separate branch starts at Mosh's pinned fcdc338 (existing pending Moss PR
#30); a stacked PR isolates the new lifecycle from that unmerged dependency.
The original Mosh pin remained unchanged during upstream implementation. The
integration candidate now records the verified dependency for reproducible Mosh
builds; this does not merge either upstream PR.
Do not merge the new PR; retain maintainer review and the compatibility checks.

## Implementation findings, 2026-10-26

Carrier readiness means one authenticated attachment, not proof of delivery to
every waiting leaf. User-originated sends/calls run in active mode; resolving
the recipient's identity can reach its selected carrier using existing packets.
Arbitrary routing between two waiting leaves on different carriers is not a new
guarantee. Presence refresh is limited to the installation's own identity/rooms
on its selected carrier; it does not restore broad overlay maintenance.

Waiting discovery and maintenance policy applies only after explicit integration.
Known-peer discovery and healthy direct startup retain their ordinary paths.
A separate common relay reliability fix upgrades large payloads over an existing
reliable stream on either leg: ordinary desktop senders also need this when
sending to a waiting recipient. This changes large-relay transport selection,
including for ordinary consumers, without enabling the waiting policy. The real
MTU-dropping relay regression and default-consumer suites cover that boundary;
it must not be described as every non-opted-in transport path being unchanged.

The candidate also corrects ordinary room-interest announcements for colocated
peers: score-only mesh backoff no longer acts as a health exclusion. Mesh score,
IP-colocation penalties and health/policy gates remain enforced. This correction
is shared by ordinary consumers; it does not enable waiting for them. Real TCP
nodes, repeated race checks and a public-network comparison cover the change.
Cold rendezvous latency remains separate from delivery over an established path.

The separately approved [connectivity contract](android-moss-connectivity-contract.plan.md)
adds an explicit network-change hint on the existing node. Android forwards
coalesced default-network changes through that entry point. It does not repeat
the activity setter to reset backoff, and a hint does not establish reachability.
Physical Wi-Fi/mobile handover and restricted-OS acceptance remain unverified.
