# Issue 94: discovery for DMs with known counterparts

Status: proposed; requires approval for a further Moss-source exception and an
additive public Go/C contract. No implementation or acceptance is claimed.

## Evidence and intended result

The [current investigation](issue-94-owner-20261023.results.md) validates the
owner's exact binaries, tests the installed Windows GUI with 800 acknowledged
messages and separately classifies current native network work. The native
fixture sends 1,728 speculative GRAFTs in two minutes and receives 1,728 PRUNEs.
Overlay value/node replies account for 68.86% of classified inbound JSON bytes.
These native counters are not the owner's OS wire budget or a causal CPU A/B.

A private same-process counterfactual now measures 96 → 0 → 96 DM rendezvous
starts per minute while other-room starts remain 32 → 32 → 32. Classified
JSON-envelope rates are 0.162 → 0.117 → 0.170 Mbit/s, and message goldens match.
It changes only known-DM topic lookups and restores normal behavior afterwards;
it is not the proposed complete policy or delivery/compatibility acceptance.

An established DM already retains its counterpart identities and requests them
through `ConnectToPeer`. Independently, each of its control/data/blob topics
keeps searching for subscribers and advertising its own topic provider record.
The intended result is to use the known recipient set for those private DMs
while retaining ordinary rendezvous for an unknown participant, a group or a
public channel. No new UI setting is needed.

## Boundary

Add an optional, per-room peer-discovery policy in Moss. It is a generic
capability that Mosh opts into; unchanged consumers, including Bastion and
gaming applications, retain today's defaults. Do not infer this policy from
a Mosh channel-name prefix inside Moss.

Proposed additive interface, with final naming checked against existing room
wrappers before implementation:

```text
SetRoomPeerDiscovery(room, Automatic | KnownPeers, peer_ids)
Moss_SetRoomPeerDiscovery(handle, room, mode, peer_ids_json) -> status
```

`Automatic` remains the default. `KnownPeers` requires a nonempty, validated
recipient set supplied by the application. It controls discovery work only;
it is neither a cryptographic membership check nor a message-authorization rule.

- Resolve the room's opaque topics through existing room mappings. Avoid
  unrelated speculative GRAFTs and topic rendezvous/provider publication for
  that explicitly configured room. Keep substrate identity publication,
  discovery, relay selection and ordinary global connectivity alive.
- Retain subscription/message handling, including a fresh counterpart GRAFT,
  direct/relay paths and retry/wakeup behavior for explicit peer targets.
  Do not add another independent peer retry scheduler.
- Treat policy updates as room-owned ephemeral state. Clear it on leave;
  restore ordinary discovery and immediate provider registration when the
  caller returns to `Automatic`. Use existing record expiry for old records.
- Leave unconfigured rooms and every existing Go/C entry point unchanged.
  No wire format, application database schema or dependency changes.

Mosh applies the policy only when the complete current recipient set is known
from its existing authenticated DM/device state. Reuse the recipients already
used for peer connection requests; do not introduce a second authority model.
Unknown identities and incomplete legacy restoration retain `Automatic`.
Linked-device admission/removal refreshes the set. Discovery hints never
replace live membership, revocation or MLS validation.

Keep Flutter bridge shapes unchanged. Use a defaulted transport operation for
non-Moss transports. An older DLL lacking the optional symbol retains ordinary
discovery; it must not silently disable delivery or fail application startup.

## Verification before shipping

1. Turn the recorded real-dependency workload into caller-visible count/byte
   regressions for the approved interface. Preserve the private counterfactual
   as attribution evidence; an idle golden is insufficient behavior proof.
2. Add caller-visible regressions for automatic/default behavior, configured
   recipients, unknown-recipient fallback, policy replacement/clearing and room
   leave/rejoin. Use actual opaque room topics, not raw channel-name matching.
3. Verify initial connection and a counterpart returning after sustained idle,
   including unavailable direct routes and actual encrypted relay delivery.
   Exercise one unmodified endpoint for mixed-version behavior.
4. Run the real linked-device, membership/removal, pending invitation, history
   recovery and audio/video call flows. Group/channel discovery must retain
   existing behavior. A successful idle counter is insufficient delivery proof.
5. Compare identical restored profiles with/without the opt-in on one host.
   Measure query/GRAFT counts and byte totals separately from CPU, with message
   goldens, topology and recording settings recorded. Repeat on Windows using
   the committed release profile; do not substitute component timing for owner
   idle acceptance.
6. Complete Go tests/race/vet, relevant Mosh Rust/Flutter checks, binding drift
   checks if generated contracts change, independent code review and CodeAnt
   comments/nitpicks. No merge or release is part of this approval.

## Risks and rollback

The main risks are incomplete recipient discovery, old invitations without a
usable identity, linked-device changes and reliance by an older endpoint on
topic rendezvous. Keep those cases automatic until their behavior is proved.
Do not ship a hard-coded Mosh exception, globally lengthened discovery timer,
or a peer cap that can displace a real call participant.

The opt-in is disabled independently of the existing default discovery path;
reverting Mosh's opt-in and the pin restores current behavior. A measured
reduction in native discovery traffic will not, by itself, close issue 94 or
establish Android background-call/battery acceptance.
