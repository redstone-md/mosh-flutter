# Issue 94: explicit retry compatibility across Moss consumers

Source audit and isolated compatibility experiment, 2026-10-21. This document
separates an implementation defect from reconnection policy; it does not
establish compatibility by running the downstream applications. No repository
production source or dependency was changed.

## Recommendation

Fix duplicate in-flight explicit-target attempts in Moss itself. There is no
evidence that this requires a Mosh-specific feature: the defect belongs to the
generic `ConnectToPeer` scheduler, and the inspected game integrations use a
different API. Keep the change confined to that scheduler.

A thirty-second failure backoff is a latency policy, not merely deduplication.
Do not describe it as harmless to every consumer. Given the requirement to
preserve other applications' recovery cadence, make that longer offline
backoff a generic optional retry policy and enable it in Mosh. Preserve the
existing default retry interval for other consumers, immediate first attempts
and renewed caller intent. Avoid a hard-coded product-name or game-profile
branch. Single-flight still needs the behavioral checks below; it is not
automatically safe merely because it is a correctness fix.

## What the current core actually changes

- `ConnectToPeer(peerID)` records a persistent target and launches a goroutine
  immediately. The maintenance loop launches another after a fixed
  `max(HandshakeTimeout, Heartbeat)` interval measured from attempt start. There
  is no per-target running-attempt check. One attempt includes direct dialing
  followed by relay fallback, so its lifetime can exceed that interval.
  [Moss cbfb21e, explicit target implementation](https://github.com/redstone-md/moss/blob/cbfb21e1fb883cec535085cd31f08534eb571681/internal/mesh/node_explicit_targets.go#L5-L71)
- This is distinct from `Moss_Connect(handle, address)`. The FFI exports these as
  separate entry points; only `Moss_ConnectToPeer` calls `Node.ConnectToPeer`.
  [FFI entry points](https://github.com/redstone-md/moss/blob/cbfb21e1fb883cec535085cd31f08534eb571681/cmd/moss-ffi/main.go#L309-L328)
- Established stream writes do not enter this scheduler: `SendStream` writes to
  an existing direct session without discovery or dialing. `OpenStream` uses
  `ResolveRoute` when necessary. **Inference:** changing only explicit-target
  scheduling does not add a delay to an existing game/SSH stream's write path.
  It can affect reconnection if an application relies on `ConnectToPeer`.
  [Stream implementation](https://github.com/redstone-md/moss/blob/cbfb21e1fb883cec535085cd31f08534eb571681/internal/mesh/node_types.go#L701-L752)
- Existing tests require explicit targets to bypass ordinary discovery/glare
  ranking and connect after previously unknown peer information appears. Those
  are compatibility obligations for the fix, not expendable test assumptions.
  [Explicit-target tests](https://github.com/redstone-md/moss/blob/cbfb21e1fb883cec535085cd31f08534eb571681/internal/mesh/explicit_target_test.go#L78-L109)

## First-party consumer evidence

| Consumer and inspected revision | Connection path | Implication for a change confined to explicit targets |
| --- | --- | --- |
| MossyMod `a51fd64b5263429e4cae01962be10bb3dbec3ce3` | JNA binds `Moss_Connect` and pub/sub; the tunnel publishes its own connection frame and waits up to ten seconds. | The inspected bridge does not expose `ConnectToPeer`, so it does not directly use this retry scheduler. Its ten-second timeout shows why changing shared discovery/pub/sub behavior would require a separate audit. |
| gse_moss `2d5ab3abd36bc9f53fd7672e1f71e9c1c7f11b61` (`dev`) | Dynamically loads `Moss_Connect` and pub/sub; calls `Moss_Connect` for configured address-based static peers. | The inspected native bridge does not load `Moss_ConnectToPeer`. Explicit peer-ID maintenance backoff therefore does not directly change these static-peer attempts. |
| MossSpore `7c72121ac03dbafabfe799354cb9561dd658901f` | Constructs a Go `moss.Node`, installs an event callback and starts it. | The inspected relay lifecycle does not register explicit application targets. Keep relay service and ordinary discovery behavior unchanged. |

Sources:

- MossyMod [complete JNA surface](https://github.com/redstone-md/MossyMod/blob/a51fd64b5263429e4cae01962be10bb3dbec3ce3/src/main/java/md/redstone/moss/MossNative.java#L11-L41)
  and [tunnel connection and timeout](https://github.com/redstone-md/MossyMod/blob/a51fd64b5263429e4cae01962be10bb3dbec3ce3/src/main/java/md/redstone/moss/MossTunnel.java#L125-L159).
- gse_moss [loaded native symbols](https://github.com/redstone-md/gse_moss/blob/2d5ab3abd36bc9f53fd7672e1f71e9c1c7f11b61/dll/moss_transport.cpp#L138-L160)
  and [static-peer connection calls](https://github.com/redstone-md/gse_moss/blob/2d5ab3abd36bc9f53fd7672e1f71e9c1c7f11b61/dll/moss_transport.cpp#L296-L301).
- MossSpore [node lifecycle](https://github.com/redstone-md/MossSpore/blob/7c72121ac03dbafabfe799354cb9561dd658901f/internal/spore/spore.go#L59-L101)
  and [configuration mapping](https://github.com/redstone-md/MossSpore/blob/7c72121ac03dbafabfe799354cb9561dd658901f/internal/spore/spore.go#L192-L240).

## Guarantees needed before integration

1. At most one explicit pipeline per target, while preserving direct-first,
   relay-fallback behavior and eventual retry after failures.
2. First intent remains immediate. A second caller during an active attempt
   must not create a parallel pipeline or lose genuinely newer intent.
3. Successful connection resets failure state. A new usable address or inbound
   connection must not remain hidden behind a stale offline cooldown.
4. Stop/restart invalidates old completions; they cannot delay a new lifecycle.
5. No retry timer or failure accounting change leaks into address-based
   `Connect`, ordinary discovery, relay promotion or stream sends. Validate
   these paths with existing real transport tests, not only scheduler tests.

These are proposed verification criteria derived from the call paths above,
not claims that a candidate implementation already meets them.

## Local compatibility counterexample

A private Go-overlay experiment exercised two real isolated Moss nodes at
`cbfb21e`, without changing repository sources or their dependency pins:

1. Register the target while its address is unknown. A diagnostic notification
   confirms the real direct attempt has read the missing target record.
2. Supply its loopback address and repeat `ConnectToPeer` during that attempt.
3. Require the direct connection within 750 ms, before periodic maintenance
   can rescue a dropped request.

The current implementation passed five of five runs in 112–114 ms. A
deliberately naive per-target guard that simply drops overlapping requests
failed five of five runs at the same deadline. This is evidence of delayed
fresh intent, not permanent connection failure. An earlier 1.2-second deadline
allowed periodic maintenance to hide the regression in two of three runs.

Both variants included the same diagnostic notification. The experiment used
`go test -overlay <variant>.json ./internal/mesh -run
'^TestOwnerRepeatedExplicitIntentAfterNewHint$' -count=5 -v`; its overlays and
raw logs remain private under `mosh-idle-network/explicit-compatibility`.
The existing selected explicit-target, discovery-budget, redial, stream/game
and lifecycle tests also passed against the unchanged implementation. This
does not validate an eventual production fix or the downstream applications.

## Limits

The audit fetched repository trees and selected first-party bridge, tunnel and
lifecycle source files at the pinned revisions. It did not rebuild Minecraft,
the Steam emulator, or the relay daemon; installed downstream library versions
may differ. No actual public first-party P2P-SSH consumer was identified, so
SSH reconnection compatibility is **unverified**. Absence of a call in the
inspected integrations does not prove that no external application uses the
public API.

The conclusion is therefore narrower than “nobody can be harmed”: the known
game bridges do not call the affected scheduler, duplicate attempt suppression
is a generic fix, and any recovery-latency change still requires explicit
behavioral checks or an opt-in policy.
