# Android connectivity signal for Moss waiting

Status: proposed; not approved or implemented. Scope: IVO-136/137 under
[IVO-132](https://linear.app/ivoxygen/issue/IVO-132/android-fonovye-zvonki-uvedomleniya-i-polnaya-dogruzka-istorii).
This supplements the approved [waiting contract](android-moss-waiting-contract.plan.md).

## Reason

The pinned library exposes no host connectivity-change signal. Existing waiting
work reacts to a failed carrier or its retry timer. Android can observe a new
default Wi-Fi/mobile network before that failure becomes visible. Repeating
the idempotent activity setter is not a connectivity signal.

## Exact additive interface

- Go: `func (n *Node) NotifyNetworkChanged() error`.
- Optional C ABI: `int32_t Moss_NotifyNetworkChanged(MossHandle handle)`.
- Invalid handle: existing -1; unstarted node: existing -3; accepted: 0.
- Nodes that never opted into activity mode, and ordinary active mode, accept
  this as a no-op. It never opts a consumer in or changes its requested mode.
- In requested waiting, coalesce one bounded attachment/liveness recheck.
  Reuse the existing probe, handshake deadline and single attachment worker;
  do not declare reachability from the OS notification alone.
- A real network event can interrupt obsolete candidate work and bypass the
  outage backoff once. Coalesce bursts and permit at most one immediate recheck
  per five seconds; later changes retain one pending recheck. Ordinary retry
  timers retain their existing backoff and ownership.
- Preserve a working carrier until its existing authenticated liveness check
  fails or a replacement is admitted. Keep one physical carrier, at most two
  during bounded handover; preserve identity, rooms and application sessions.
- Add no packet, wake payload, routing permission, dependency or persisted schema.
  Existing consumers retain their defaults and current ABI symbols.

## Android integration and checks

The installation-owned adapter observes actual default-network changes through
the existing ACCESS_NETWORK_STATE grant, coalesces callbacks and invokes this
optional symbol. A missing symbol is reported as unsupported immediate network
recovery; it never triggers mode toggling or a second Moss node.
Use callback-supplied capabilities/link properties; do not synchronously query
them inside onAvailable. Losing default status alone does not prove the old
connection died. Observe the application default; do not bind a second network.

Verify the public node/C boundary with real carriers: duplicate notifications,
healthy-carrier preservation, obsolete candidate cancellation, unavailable
network/backoff, Stop races and unchanged non-opted consumers. Actual Wi-Fi to
mobile transitions, Doze and delivery latency still require a physical phone.

Repository approval is required because AGENTS.md says: "Ask before changing
public contracts, dependencies, schemas or deleting tracked code." This proposal
does not authorize implementation until the owner approves it.

Source: [Android network-state callbacks](https://developer.android.com/develop/connectivity/network-ops/reading-network-state),
checked after Context7 returned no exact default-callback reference.
