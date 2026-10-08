# Issue 46: relay capacity and directed media

Research date: 2026-10-08. Design evidence and recommendations only. No runtime,
benchmark, dependency, configuration or Moss change was made.

Moss was inspected at commit `0effb8bb2cd318d2fb516cd2689083daaa5a1917`.
Native libwebrtc headers and test transport were checked at upstream commit
`e40a408898b7ea16e59ebc8ea96c6d42c8f8753d`. Context7 was queried for WebRTC and
Flutter WebRTC. It found the plugin's PeerConnection documentation but no native
custom-transport documentation, so the native API findings use official source.

## Recommendation

Use a bounded, negotiated media allowance on a directed Moss carrier. Keep a
separate aggregate relay upload/download budget and preserve capacity for messages
and control traffic. A capable relay can offer more capacity under its own policy;
the calling client cannot increase another node's allowance. Raising every Mosh
node's relay defaults does not establish capacity for a particular call.

This is a proposed transport policy, not an accepted API or measured video target.
The agreed 720p/30 fps target applies only to a sufficient path. The encoder must
reduce or pause video when measured or admitted capacity falls below its needs.
See the [issue 46 plan](issue-46-video-calls.plan.md).

## What the pinned relay actually limits

| Setting or bound | Default and actual unit | Scope and behavior |
| --- | --- | --- |
| `nat.relay_max_bandwidth_kbps` | `256`, multiplied by `1024` to obtain a byte bucket capacity | Despite the name, this is not a kilobits/s rate. `security.rate_limit_burst` also caps the capacity. |
| `security.rate_limit_burst` | `256000` bytes | Clamps the relay bucket's burst capacity to 256,000 bytes at the defaults. |
| `nat.relay_sustained_kibps` | `0`, deriving refill as burst/4 | A positive value requests KiB/s, then clamps to bucket capacity. It bypasses the legacy sustained governor. |
| `security.rate_limit_sustained` | `64000` bytes/s | Caps the derived refill when no explicit sustained KiB/s value exists. Default effective refill is 64,000 bytes/s, or 512,000 bits/s. |
| `nat.relay_consumer_cap_bytes` | `0`, disabled | Approximate rolling minute quota per source peer, across that source's relay sessions. Crossing it closes the offending route and resets that source's quota entry. |
| `nat.relay_max_sessions` | `50` sessions | Node-wide count admission limit. This does not reserve bandwidth or impose an aggregate byte rate. |
| `nat.relay_session_ttl_sec` | `1800` seconds | Idle session lifetime. Forwarded traffic refreshes it. |
| `security.max_message_size_bytes` | `65536` bytes | Raw application payload cap for publish, directed send and streams. Larger application frames need packetization. |
| Relay payload hard cap | `190 * 1024` bytes | Wire payload cap. Directed relay sealing requires 28 extra bytes, so its plaintext limit is lower. Relayed stream wrapping adds another 8 bytes. |
| Transport data-frame hard cap | `256 * 1024` bytes | Encoded post-handshake frame cap. This is not an application payload size or UDP MTU. |
| FFI relay open budget | `5` seconds | Existing sessions are reused; opening a session divides the budget across candidates. |
| `security.handshake_timeout_sec` | `5` seconds | Default handshake timeout. Stream writes have a separate hard-coded 5-second write deadline. |
| `max_peers` | `200` direct peers | A separate endpoint relayed-peer cap is `max(2, max_peers)`. Neither number reserves throughput. |

Defaults and fields come from [config definitions and defaults][config]; the
effective burst/refill formula comes from [relayRateLimits][rates]. Buckets are
keyed by the authenticated immediate source peer. The two directions of one call
consume their respective source buckets. Several calls from the same source share
its bucket. The relay charges application bytes after subtracting its fixed AEAD
expansion, not physical network bytes. See [forwarding and charge checks][forward]
and [AEAD accounting][seal].

There is a documentation discrepancy. The `NATConfig` comment calls the minute
consumer quota per relay session, but `relayConsumerCapped(peer.id, ...)` keys it
by source peer. The implementation uses a weighted current/previous minute
estimate and deletes the entry when it trips. It is not a durable monthly quota.
This quota counts the encrypted relay payload length; the token bucket instead
subtracts the relay AEAD expansion. Neither counter includes outer JSON/base64
or IP/transport headers.
See [quota implementation][quota] and [rolling counter][counter].

The inspected forwarding path has no aggregate relay byte-rate bucket and no
media-class allowance. It checks route/source identity, the payload size,
per-source tokens and the optional per-source minute quota. It then sends the
payload. A token refusal drops the packet and demotes the relay's advertised
supernode status for an overload cooldown. Further refusals extend that cooldown.
The default cooldown is two heartbeats with a 500 ms minimum. At an ordinary
Moss default heartbeat it is 2 seconds; Mosh's 250 ms heartbeat yields 500 ms.
See [relay forwarding][forward], [overload behavior][overload] and
[Mosh configuration](../../mosh-core/src/moss_ffi/config.rs).

`telemetry.bandwidth_cap_bytes` clamps reported private statistics. It does not
limit actual forwarding. See [telemetry aggregation][telemetry].

Peer counts and relay admission are checked separately from these byte budgets.
See [endpoint relay peer admission][peer-cap] and [session admission][admission].

## Why a caller-side configuration increase is insufficient

Mosh currently changes discovery, port mapping, hole-punch attempts and heartbeat
settings, while leaving relay rates at Moss defaults. These settings apply to
the local node. The middle relay enforces its own `n.config` when receiving traffic.
See [Mosh configuration](../../mosh-core/src/moss_ffi/config.rs), [rates][rates]
and [forwarding][forward].

Increasing only `relay_max_bandwidth_kbps` can have no effect because the security
burst clamp remains. Increasing only `security.rate_limit_sustained` can also have
no effect because the derived refill remains burst/4. An explicit sustained
KiB/s setting changes the local relay's policy, subject to its burst capacity.
None of these settings negotiates capacity from a foreign relay. This follows
from the [rate calculation][rates].

A blanket higher default would authorize more forwarding by every eligible local
relay, across all sources. Session counts do not describe that combined cost.
For example, 50 admitted calls each carrying 1.5 Mb/s in both directions would
require 150 Mb/s of relay ingress and 150 Mb/s of relay egress before overhead.
This is arithmetic, not an achievable-rate claim or the current default allowance.

## Illustrative bandwidth cost

Assume one relay carries both directions and each endpoint sends **1.5 Mb/s of
video payload**. These are decimal bits and bytes. Audio and all overhead are
excluded.

| Quantity | Calculation | Result |
| --- | --- | --- |
| One endpoint's video upload | `1,500,000 / 8` | 187,500 bytes/s |
| Relay ingress | `2 * 1.5` | 3 Mb/s |
| Relay egress | `2 * 1.5` | 3 Mb/s |
| Aggregate relay interface traffic | `(3,000,000 + 3,000,000) / 8` | 750,000 bytes/s |
| Aggregate interface traffic in one hour | `750,000 * 3600` | 2,700,000,000 bytes, or 2.7 GB, about 2.515 GiB |

Each 187,500 bytes/s source exceeds the pinned 64,000 bytes/s sustained bucket.
Audio, RTP/RTCP, stream headers, encryption, retransmissions and transport headers
increase the load. The relay's JSON envelope also base64-encodes binary payloads,
so interface traffic is materially higher than the payload-only calculation.
See [relay envelope format and size accounting][relay-cap]. A negotiated allowance
must say whether its unit counts media payload bytes or wire bytes; node-wide
network budgets should account for actual transmitted/received bytes.

## Carriers and message fairness

Moss already exports directed peer packets, async directed packets and streams.
Directed packets use an established session or native relay. Streams use the
direct mux and an 8-byte wrapper on relay fallback. There is no separate raw UDP
datagram or unreliable-stream C export. The Go-only latest-wins option changes
queue overflow behavior, not the reliability of the underlying connection.
See [Moss API][api], [C exports][ffi] and [stream policy][stream-policy].

Mosh wraps streams but not the directed packet API. Its DM adapter fixes stream
ID 2; its current voice hub publishes to a room rather than the selected device.
See [Rust loaded symbols](../../mosh-core/src/moss_ffi/runtime.rs),
[DM stream adapter](../../mosh-core/src/private_dm_runtime/transport.rs), and
[voice hub](../../mosh-core/src/private_dm_runtime/call_media.rs).

Current queue isolation is useful but does not establish traffic priority:

- The generic outbound envelope queue has 64 slots per peer. It drops on overflow.
  Directed sends can share it with gossip. See [outbound queue][outbound].
- Directed receive dispatch has 256 slots per authenticated source, behind a
  shared 1,024-slot dispatcher. Both can drop. See [directed delivery][directed]
  and [node setup][setup].
- Default transport stream and UDP queues have 256 packets. The high-throughput
  preset raises them to 65,536. See [transport configuration][config] and
  [API transport tuning][api]. Larger queues add memory and may retain stale
  media; they do not fix a slow link.
- Session writes share a write lock across mux streams. A separate media stream
  cannot alone prevent chat/control writes waiting behind media or TCP delivery.
  See [session write serialization][session]. UDP packets use one socket send
  per packet, without application fragmentation in that carrier. See [UDP write][udp].

These facts support a dedicated directed media contract and explicit scheduling,
rather than a global queue-size or rate-limit increase.

## Proposed long-term boundary

Mosh should own call selection, camera consent, media encoding/rendering and the
authenticated media keys. Moss should own the selected-peer route, capacity
admission, packet scheduling and feedback about that route. The media engine
should receive real send/receive timing and loss feedback and adapt encoding.
These are proposed responsibilities, not existing contracts.

The minimum transport policy should include:

1. A node-wide bounded relay ingress/egress and queue-memory budget, plus source
   limits. Relay contribution remains the local operator's policy.
2. A short-lived media allowance tied to authenticated endpoints and the selected
   call, with explicit requested/granted rates, expiry and refusal. Peers cannot
   promote arbitrary bulk bytes to an unlimited priority class.
3. Reserved bounded service for call/network control and messages, then audio,
   then video. Bulk traffic uses remaining service. Protect message progress from
   continuous media, and protect audio from bursts of video keyframes.
4. Packet deadlines and bounded queues measured in bytes and age. Drop stale video
   rather than accumulate seconds of delay. Report pressure so the engine can
   reduce bitrate/resolution/frame rate or pause video.
5. Directed packets to the chosen device only. Preserve receiver identity,
   cancellation and authenticated end-to-end media encryption across relay changes.
6. Capacity checks on both directions and every relay leg. A route migration must
   establish its allowance again. Reuse existing Moss discovery and willing relays;
   no new mandatory central server follows from this design.

This can be an additive Moss capability, as the user authorized future Moss work.
It requires its own implementation and verification. The current relay protocol
does not provide the negotiation or scheduling above. Admission must not claim
available capacity solely from the client's requested rate.

## Native WebRTC engine feasibility

Official libwebrtc source does provide a lower-level custom transport boundary.
`Transport` has `SendRtp` and `SendRtcp`; video and audio send-stream configs accept
an application-owned `Transport*`. See [transport interface][webrtc-transport],
[video config][webrtc-video] and [audio config][webrtc-audio]. `Call::Receiver()`
exposes RTP/RTCP delivery, and `Call` has network-state and sent-packet hooks.
See [Call interface][webrtc-call] and [packet receiver][webrtc-receiver].

Upstream's `DirectTransport` test exercises this boundary, including received RTP,
RTCP and sent-packet notifications. This is source evidence that a custom packet
carrier is possible below PeerConnection, not proof of a production Moss adapter.
See [upstream test transport][webrtc-test].

Moss itself uses external STUN clients and its own encrypted relay protocol.
Its browser-only WebRTC adapter receives an already-established DataChannel and
leaves ICE/signaling to JavaScript. See [NAT observation][stun],
[UDP packet handling][stun-handler] and [browser adapter][wasm]. A stock
`RTCPeerConnection` does not gain Moss relay support from those APIs.

No existing Flutter WebRTC transport adapter has been established. Context7's
[official plugin source](https://github.com/flutter-webrtc/flutter-webrtc/blob/main/lib/src/native/rtc_peerconnection_impl.dart)
documents PeerConnection and ICE operations. The verified native option needs a
bounded C++ adapter, versioned builds, device capture/playout/rendering integration,
RTP/RTCP and codec negotiation, thread ownership, encryption, and accurate network
feedback. Do not claim its packaging, hardware acceleration or 720p/30 fps quality
on macOS/Windows/Linux without a native proof. The available APIs justify a focused
spike; they do not select the stack by themselves.

[config]: https://github.com/redstone-md/moss/blob/0effb8bb2cd318d2fb516cd2689083daaa5a1917/internal/mesh/config.go#L208-L305
[rates]: https://github.com/redstone-md/moss/blob/0effb8bb2cd318d2fb516cd2689083daaa5a1917/internal/mesh/node_relay_selection.go#L14-L70
[forward]: https://github.com/redstone-md/moss/blob/0effb8bb2cd318d2fb516cd2689083daaa5a1917/internal/mesh/node_relay_control.go#L172-L226
[seal]: https://github.com/redstone-md/moss/blob/0effb8bb2cd318d2fb516cd2689083daaa5a1917/internal/mesh/node_relay_transport.go#L317-L332
[quota]: https://github.com/redstone-md/moss/blob/0effb8bb2cd318d2fb516cd2689083daaa5a1917/internal/mesh/node_relay_control.go#L635-L671
[counter]: https://github.com/redstone-md/moss/blob/0effb8bb2cd318d2fb516cd2689083daaa5a1917/internal/mesh/node_types.go#L412-L438
[overload]: https://github.com/redstone-md/moss/blob/0effb8bb2cd318d2fb516cd2689083daaa5a1917/internal/mesh/node_relay_control.go#L310-L341
[telemetry]: https://github.com/redstone-md/moss/blob/0effb8bb2cd318d2fb516cd2689083daaa5a1917/internal/stat/aggregator.go#L190-L205
[relay-cap]: https://github.com/redstone-md/moss/blob/0effb8bb2cd318d2fb516cd2689083daaa5a1917/internal/mesh/node_relay_control.go#L14-L25
[api]: https://github.com/redstone-md/moss/blob/0effb8bb2cd318d2fb516cd2689083daaa5a1917/docs/API.md
[ffi]: https://github.com/redstone-md/moss/blob/0effb8bb2cd318d2fb516cd2689083daaa5a1917/cmd/moss-ffi/main.go
[stream-policy]: https://github.com/redstone-md/moss/blob/0effb8bb2cd318d2fb516cd2689083daaa5a1917/internal/mesh/node_types.go#L584-L605
[outbound]: https://github.com/redstone-md/moss/blob/0effb8bb2cd318d2fb516cd2689083daaa5a1917/internal/mesh/node_gossip_control.go
[directed]: https://github.com/redstone-md/moss/blob/0effb8bb2cd318d2fb516cd2689083daaa5a1917/internal/mesh/node_dispatch_bootstrap.go#L18-L75
[setup]: https://github.com/redstone-md/moss/blob/0effb8bb2cd318d2fb516cd2689083daaa5a1917/internal/mesh/node_lifecycle.go#L106-L150
[session]: https://github.com/redstone-md/moss/blob/0effb8bb2cd318d2fb516cd2689083daaa5a1917/internal/transport/conn.go#L66-L87
[udp]: https://github.com/redstone-md/moss/blob/0effb8bb2cd318d2fb516cd2689083daaa5a1917/internal/transport/udp_session.go#L157-L179
[stun]: https://github.com/redstone-md/moss/blob/0effb8bb2cd318d2fb516cd2689083daaa5a1917/internal/mesh/node_reachability.go#L30-L55
[stun-handler]: https://github.com/redstone-md/moss/blob/0effb8bb2cd318d2fb516cd2689083daaa5a1917/internal/transport/udp_handshake.go#L65-L89
[wasm]: https://github.com/redstone-md/moss/blob/0effb8bb2cd318d2fb516cd2689083daaa5a1917/internal/transport/webrtc_js.go#L1-L21
[peer-cap]: https://github.com/redstone-md/moss/blob/0effb8bb2cd318d2fb516cd2689083daaa5a1917/internal/mesh/node_relay_control.go#L527-L585
[admission]: https://github.com/redstone-md/moss/blob/0effb8bb2cd318d2fb516cd2689083daaa5a1917/internal/nat/relay.go#L61-L81
[webrtc-transport]: https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/api/call/transport.h
[webrtc-video]: https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/call/video_send_stream.h
[webrtc-audio]: https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/call/audio_send_stream.h
[webrtc-call]: https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/call/call.h
[webrtc-receiver]: https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/call/packet_receiver.h
[webrtc-test]: https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/test/direct_transport.cc
