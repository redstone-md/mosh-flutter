# Private DM (slice one)

Feature doc for the slice-one private-DM flow under the Flutter + Rust bridge.
Scope: invite create -> paste -> accept -> fingerprint confirm -> send ->
snapshot poll. Reference: [ADR 0013](../ADR/0013-fork-topology-and-temporary-fake-gateway.md),
[Architecture](../Architecture.md).

The flow runs through the `Gateway` seam. The app always runs
`RealBridgeGateway` (real `mosh_core` via `flutter_rust_bridge`); widget tests
override the provider with `ScriptableGateway` from `test/support/`. The
sequence below is the real path.

## Invite -> confirm -> send (Real path)

```mermaid
sequenceDiagram
    autonumber
    participant Alice as Alice (Dart UI)
    participant GW as Gateway / RealBridgeGateway
    participant Api as api::private_dm (Rust)
    participant Bob as Bob (Dart UI)

    Alice->>GW: createInvite(StartSessionRequest)
    GW->>Api: create_invite(request)
    Api-->>GW: InviteCreated { inviteUri, fingerprint }
    GW-->>Alice: InviteCreated
    Note over Alice: share invite URI out-of-band
    Bob->>Bob: parse mosh://invite?...#fp= via invite_uri.dart
    Note over Bob: invite_detection.dart watches clipboard
    Bob->>GW: acceptInvite(AcceptInviteRequest)
    GW->>Api: accept_invite(request)
    Api-->>GW: SessionSnapshot { fingerprint }
    GW-->>Bob: SessionSnapshot
    Bob->>Bob: verify fingerprint == SessionSnapshot.fingerprint
    Note over Bob: slice one: local confirm flag<br/>later slice: gateway mutation
    Bob->>GW: send(DmTarget(sessionId), body)
    GW->>Api: send_message(session_id, body)
    Api-->>GW: SendMessageResult
    GW-->>Bob: done
    Bob->>GW: poll(DmTarget(sessionId)) via activeSessionProvider.family
    GW->>Api: poll_session(session_id)
    Api-->>GW: SessionSnapshot { messages[] }
    GW-->>Bob: SessionSnapshot
    Note over Bob: message appears in snapshot
```

## Slice-one boundaries

- Poll-based, no streams. `api::private_dm` exposes no `StreamSink` in slice
  one (the React frontend polled on `AUTO_POLL_MS`); the Dart DM screen
  re-polls via `activeSessionProvider.family`.
- Fingerprint confirm is a UI-side gate in slice one: the Dart orchestration
  blocks `Gateway.send` until the user confirms the safety number. Later
  slices move the confirmation to a gateway mutation.
- `mosh://invite?...#fp=...` is parsed by ported `invite_uri.dart`; manual
  paste only, no OS deep-link association (ADR 0015).
- Sessions list and per-session snapshot come from `sessionListProvider` and
  `activeSessionProvider.family`; both consume `gatewayProvider`, never a
  concrete `Gateway` (ADR 0013).

## Proof

The Real path is proven end-to-end by
`integration_test/slice_one_test.dart` against a real `mosh_core.dll`:
`appDiagnostics`, `nativeRuntimeStatus`, `listSessions`, and `createInvite`
all run through `RealBridgeGateway`. See ADR 0013 Final Status.
