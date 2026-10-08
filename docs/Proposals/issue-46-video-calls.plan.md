# Issue 46: video calls between contacts

Design interview in progress. This document records agreed requirements and
open decisions for [issue 46](https://github.com/redstone-md/mosh-flutter/issues/46).

## Agreed requirements

- Start a call from a private DM; the contact can accept or decline.
- macOS and Windows require full acceptance testing. Preserve Linux behavior
  and verify it with available tooling. Android and iOS follow later.
- All call media uses Moss, including direct and relayed paths. Reuse its
  discovery and NAT traversal; add Moss capabilities when needed. No new
  mandatory server infrastructure. Media-library choice remains open.
- Ring the contact's available linked devices. An answer selects one receiving
  device; other devices stop ringing. See [ADR 0043](../ADR/0043-one-device-per-user-in-a-call.md).
- Explicit decline on one receiving device ends the pending call on all devices.
- Audio and video belong to one call. Either participant can enable or disable
  their camera during a voice or video call without starting another call.
- Accepting a call does not automatically enable the receiving camera. Camera
  permission refusal preserves voice calling.
- Incoming calls require a running application, including minimized windows.
  Delivery after the application exits is outside this issue.
- All participating clients upgrade together. Do not add a compatibility layer
  for the existing call protocol or older client versions.
- Adapt video quality to available bandwidth and prioritize audio. Target
  720p at 30 fps on a sufficient connection; reduce or pause video on a weak path.
- Recover a disconnected call for up to 15 seconds with a visible connecting
  state, then end it if the connection has not recovered.
- Screen sharing, recording, call transfer and chat call-history entries belong
  to separate tasks.

Domain terms live in [GLOSSARY.md](../../GLOSSARY.md); existing user and device
identity definitions live in [CONTEXT.md](../../CONTEXT.md).

## Existing implementation and constraints

- Voice calls already use real Moss transport, native Opus/CPAL, Dart AES-GCM,
  and a separate desktop controls process. See [voice calls](../Features/voice-calls.md).
- Existing call controls do not select an authenticated receiving device or
  coordinate competing answers. The video design must settle device selection
  and authorization rather than extending that ambiguity.
- The controls process currently receives presentation metadata and commands,
  with no media frames, call keys or native runtime. Video rendering needs an
  explicit process boundary.
- At the pinned Moss commit `0effb8bb2cd318d2fb516cd2689083daaa5a1917`, NAT
  traversal and relay use Moss's own protocol. The native C API does not expose
  a standard TURN endpoint usable as an ICE server by `RTCPeerConnection`.
  See [Moss carriers](../../moss/docs/API.md).
- Moss exports directed peer packets and streams. Mosh already wraps streams;
  directed peer packets are not yet wrapped. The current voice hub publishes
  room frames rather than directing them to selected devices.
- The pinned relay defaults allow 64,000 bytes/s sustained per source peer,
  approximately 512 kbit/s, with excess packets dropped. Application payloads
  default to a 65,536-byte cap. These are static implementation findings,
  not a measurement of achievable video quality.
- Moss already exposes `nat.relay_sustained_kibps` to raise a relay's local
  allowance. The inspected forwarding path has no aggregate bandwidth budget;
  per-source limits and session counts do not reserve capacity for a call.
- [ADR 0012](../ADR/0012-port-strategy-what-goes-to-dart-vs-mosh-core.md) proposes
  native media crypto/buffers, while the current voice implementation keeps
  them in Dart. Resolve the intended boundary when choosing the media stack.

## Design evidence

- [Call concurrency](issue-46-call-concurrency.research.md): Telegram reserves
  the receiving account before answer and selects one device. Mosh must choose
  its own admission policy when linked devices cannot communicate.
- [Relay capacity and directed media](issue-46-relay-media.research.md): actual
  limits and units, configuration, traffic cost and proposed capacity policy.
- [Media engine and desktop ownership](issue-46-media-engine.research.md):
  native libwebrtc and RingRTC transport hooks, packaging gaps and video IPC.

Source inspection establishes candidate APIs, not a working Moss media engine.
Native packaging, media protection and real-device quality require a focused
feasibility check before replacing the working voice pipeline.

## Open decisions

- User-wide versus device-local busy behavior, when to reserve the user, and
  how concurrent answers and outgoing calls resolve.
- A unified native audio/video engine, its reproducible packaging and directed
  Moss integration; media encryption/key ownership and desktop process ownership.
- Camera activation before answer, device selection and permission failures.
- Relay capacity, bandwidth policy and safeguards for message delivery.
- Acceptance scenarios and observable quality targets on real desktop hosts.

## Checks and risks

Use existing widget adapters and independent real Moss processes. Preserve the
voice baseline, navigation and window lifecycle while adding video incrementally.
Implementation checks include Flutter analyze/tests/format, Rust tests/fmt/clippy,
and bridge generation/drift checks if native API signatures change.

Primary risks are competing device answers, unauthenticated control messages,
media queue latency, relay capacity, video crossing the desktop process boundary,
and regressions in working voice calls. No production code has changed.
