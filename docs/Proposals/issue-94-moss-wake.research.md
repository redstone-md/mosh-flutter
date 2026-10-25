# Issue 94: reusing Moss relays for Android wake signaling

Date: 2026-10-25.
Status: Feasibility research, not an approved runtime change.
Mosh baseline: `v0.24.3`; Moss pin:
`fcdc3383601cf3fb5232ba1ae1ffe262b552555e`.
Related: [background design](issue-94-android-background.plan.md).

## Result

An unchanged Moss relay can carry encrypted data between two running endpoints,
including a leaf with one direct attachment. Reusing that carrier is viable.
The pinned runtime does not provide a background mode that suspends the mesh
while preserving a designated wake connection through the current C ABI.
It also does not wake an Android process or retain events for an offline leaf.

This separates two claims: live forwarding was exercised; low-power Android
waiting and recovery after process reclamation have not been established.
No Moss sources, public contracts, dependencies or application behavior changed.

## Source evidence

| Question | Finding |
| --- | --- |
| Can an existing relay carry the signal? | Yes. Directed packets and relayed application payloads already exist. A transport acceptance is not a delivery receipt. See [Rust packet boundary](../../mosh-core/src/moss_ffi/packets.rs), [relay API](../../moss/internal/mesh/node_relay_api.go), and [relay payload protection](../../moss/internal/mesh/node_relay_transport.go). |
| Can a disconnected phone receive it later? | No queue exists. The intermediary requires the target in its peer table; a missing target cannot receive a relay request or data. See [relay control](../../moss/internal/mesh/node_relay_control.go) and [documented limitations](../../moss/docs/KNOWN_LIMITATIONS.md). This concerns the Moss carrier, not Mosh's separate persistent outbox/retry behavior. |
| Can Mosh suspend everything except one connection? | No pause/resume, live configuration update or client-mode operation exists in the exported API. [Rust symbol loading](../../mosh-core/src/moss_ffi/runtime.rs) and the rebuilt library's 37 exported `Moss_*` symbols confirm the current boundary. |
| Would Stop preserve that connection? | No. [Moss_Stop](../../moss/cmd/moss-ffi/main.go) removes the C handle. [Node.Stop](../../moss/internal/mesh/node_lifecycle.go) cancels workers, clears peers/routes and closes listeners and sessions. |
| Do the existing room controls suffice? | No. [KnownPeers discovery](../../moss/internal/mesh/node_room_discovery.go) limits a room's rendezvous/speculative recipient work. It is neither a global suspend policy nor a peer admission allowlist. |
| Can startup configuration reduce work? | Trackers, DHT, LAN and port mapping can be disabled explicitly, and static peers supplied. [Node startup](../../moss/internal/mesh/node_lifecycle.go) still starts maintenance/bootstrap/overlay workers. [Config parsing](../../moss/internal/mesh/config.go) treats zero gossip/relay numeric settings as defaults, not an off switch. |
| Does max_peers=1 guarantee the desired wake attachment? | It caps direct capacity, not the identity of the retained attachment or every relayed endpoint. Go-level admission controls are not exported through the C ABI. |
| Is a live leaf already cheap enough? | Unmeasured. Current Mosh sets a 250 ms heartbeat; healthy peer probes have a 15 s floor, or the configured heartbeat if longer. Lower byte counts alone do not establish mobile-radio battery use. See [Mosh config](../../mosh-core/src/moss_ffi/config.rs) and [maintenance](../../moss/internal/mesh/node_maintenance.go). |

An intentionally reduced startup profile is not disproved by the missing
dynamic mode. It would still need measured idle work, stable attachment
selection, safe foreground/background transitions and restoration of existing
rooms/streams. Destroying and recreating the installation's shared node without
coordinating its owners would not meet those requirements.

## Verification performed

Prepared the pinned native runtime with `node scripts/moss-prepare.mjs`.
No source changes were made inside the Moss submodule; its working tree
remained clean.

Ran the following existing tests with Go 1.25.9, `-mod=readonly`, `-count=1`
and a 90-second package timeout: **15 passed, 0 failed, none skipped/missing**.

```text
TestParseConfigRespectsExplicitEmptyTrackers
TestParseConfigPreservesPartialNestedOverrides
TestDefaultOfflineConfigIsOffline
TestDefaultConfigIsNotOffline
TestKnownRoomDoesNotProbeUnrelatedPeers
TestRoomDiscoveryValidationAndLeave
TestKnownRoomReplacesHintsAndAcceptsNewSubscription
TestSendToPeerDirectConnectedSendsWithoutRelay
TestSendToPeerRelayedFallbackForDisconnectedPeer
TestDMSealedAgainstRelay
TestSendRelayPayloadSealsOnWire
TestDisconnectedRelayTargetAnswersStaleTrafficOnce
TestDisconnectedRelayRoutesKeepBoundedRetirementState
TestStopClearsRelayState
TestExplicitRelayAdmissionRetainsWorkingSession
```

The last test uses three real running nodes, a caller/target with one direct
slot each, and a shared core. Discovery is disabled. The fixture marks the
loopback core publicly reachable and supplies its signed relay advertisement;
this is not evidence about every public volunteer relay. It verifies one
relayed peer and application delivery, not Android wake or energy use.
Other selected tests exercise config, room policy, authenticated encryption
and disconnected/retired routes using their existing fixtures.

An additional standalone C-ABI probe loaded the freshly built library, opened
an ephemeral identity without a key-store callback or application profile,
and disabled trackers/DHT/LAN/port mapping/static peers. Results:

```text
Moss_Init: positive handle
Moss_Start(handle): 0
Moss_Stop(handle): 0
Moss_Start(the same handle): -1 (invalid handle)
Moss_GetMeshInfo(the same handle): null
```

This verifies the difference between Go-level Node restart tests and the
destructive exported Stop operation that Mosh actually calls.
The tested library SHA-256 was
`b292238a6aba49a50917b58a9dccbadfb955fbad57b9db6436af679af0f65d9a`.
Private probe code and machine-readable results are retained outside the
repository under `/root/private/mosh-android-background-research/`.

No physical Android device was attached. These checks establish no battery
budget, wake latency, Doze/OEM reliability or cold locked-state access policy.

## Additional Google dependency to resolve

The pinned [STUN defaults](../../moss/internal/mesh/config.go) include Google
endpoints before other providers. [STUN selection](../../moss/internal/mesh/node_reachability.go)
can use them when the node has public bootstrap trackers or a non-loopback
static peer, even if DHT and LAN discovery are disabled.
This is separate from FCM and Google Play services. Removing FCM alone does
not establish a no-Google-network-contact policy. The current config has no
provider-list override, so the intended privacy requirement needs to be explicit.

## Design implications

The existing relay carrier merits reuse; a new hosted broker is not proven
necessary. A dedicated opt-in waiting policy in Moss is a candidate for
maintainer discussion, with current desktop/gaming/SSH behavior preserved.
It would need an explicit lifecycle and attachment policy rather than a
collection of hidden timer changes. A separate Google-free wake transport
remains an alternative if modifying Moss is unsuitable.

Before selecting either approach, settle:

- Whether the receiver retains a small live Moss endpoint or uses another
  receiving transport; how attachments are selected, renewed and replaced.
- Android foreground-service/exemption behavior, process reclamation and force
  stop boundaries; these are not solved by the relay carrier.
- Authenticated wake events, expiry, replay/abuse limits and which durable state
  is available before app unlock. The relay cannot authorize a call.
- Measured idle CPU, wakeups, radio traffic and battery use on physical phones,
  while preserving foreground discovery, message recovery and active calls.

No API, wire format or upstream implementation is authorized by this research.
