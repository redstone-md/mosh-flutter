# Issue 46: video calls between contacts

Design interview in progress. This document records agreed requirements and
open decisions for [issue 46](https://github.com/redstone-md/mosh-flutter/issues/46).

## Agreed requirements

- Start a call from a private DM; the contact can accept or decline.
- macOS and Windows require full acceptance testing. Preserve Linux behavior
  and verify it with available tooling. Android and iOS follow later.
- Reuse Moss discovery, NAT traversal and relay capability. No new mandatory
  server infrastructure. Library choice remains open.
- Ring the contact's available linked devices. An answer selects one receiving
  device; other devices stop ringing. See [ADR 0043](../ADR/0043-one-device-per-user-in-a-call.md).
- Audio and video belong to one call. Either participant can enable or disable
  their camera during a voice or video call without starting another call.
- Accepting a call does not automatically enable the receiving camera. Camera
  permission refusal preserves voice calling.
- Incoming calls require a running application, including minimized windows.
  Delivery after the application exits is outside this issue.

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
- [ADR 0012](../ADR/0012-port-strategy-what-goes-to-dart-vs-mosh-core.md) proposes
  native media crypto/buffers, while the current voice implementation keeps
  them in Dart. Resolve the intended boundary when choosing the media stack.

## Open decisions

- Decline on one linked device, concurrent answers, concurrent outgoing calls,
  and another incoming call while a device is busy.
- Whether every media path must use Moss or a separate direct media connection
  is allowed without new mandatory infrastructure.
- Media engine, directed Moss carrier, encryption/key ownership, and desktop
  capture/decode/render ownership.
- Camera activation before answer, device selection and permission failures.
- Old-client compatibility, quality adaptation and reconnect behavior.
- Call history, screen sharing, recording and device transfer scope.
- Acceptance scenarios and observable quality targets on real desktop hosts.

## Checks and risks

Use existing widget adapters and independent real Moss processes. Preserve the
voice baseline, navigation and window lifecycle while adding video incrementally.
Implementation checks include Flutter analyze/tests/format, Rust tests/fmt/clippy,
and bridge generation/drift checks if native API signatures change.

Primary risks are competing device answers, unauthenticated control messages,
media queue latency, relay capacity, video crossing the desktop process boundary,
and regressions in working voice calls. No production code has changed.
