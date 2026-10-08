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
- Occupancy belongs to the user. A pending outgoing or admitted incoming call
  reserves it through ringing, setup, active media and reconnection. A free sibling
  cannot admit an unrelated call while that occupancy is known.
- A remaining reachable device can call without permission from unavailable
  siblings. User-wide occupancy is best effort during network partitions;
  different devices can temporarily hold overlapping calls. The rule after
  detecting that conflict remains open.
- Audio and video belong to one call. Either participant can enable or disable
  their camera during a voice or video call without starting another call.
- Accepting a call does not automatically enable the receiving camera. Camera
  permission refusal preserves voice calling.
- A missing or refused microphone does not prevent receiving audio/video.
  Show its unavailable state and allow enabling a working microphone later.
- Incoming calls require a running application, including minimized windows.
  Delivery after the application exits is outside this issue.
- All participating clients upgrade together. Do not add a compatibility layer
  for the existing call protocol or older client versions.
- Adapt video quality to available bandwidth and prioritize audio. Target
  720p at 30 fps on a sufficient connection; reduce or pause video on a weak path.
- Hardware encoding is not a prerequisite for the first release. A software
  candidate must demonstrate the quality target without overheating, material
  latency or UI slowdown; compare established products' hardware paths.
- Recover a disconnected call for up to 15 seconds with a visible connecting
  state, then end it if the connection has not recovered.
- Screen sharing, recording, call transfer and chat call-history entries belong
  to separate tasks.
- Use one established native audio/video engine in the main process. The child
  desktop call window receives bounded frames and sends commands; its failure
  must preserve the call and main-view controls. See
  [ADR 0044](../ADR/0044-native-call-media-over-moss.md).
- Bound relay capacity at node and flow levels. Preserve capacity for messages
  and control; prioritize audio over video. Choose numeric budgets from measurements.

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
  them in Dart. [ADR 0044](../ADR/0044-native-call-media-over-moss.md) adopts native
  media ownership for this feature; the existing pipeline has not yet changed.

## Design evidence

- [Call concurrency](issue-46-call-concurrency.research.md): Telegram reserves
  the receiving account before answer and selects one device. Mosh must choose
  its own admission policy when linked devices cannot communicate.
- [Relay capacity and directed media](issue-46-relay-media.research.md): actual
  limits and units, configuration, traffic cost and proposed capacity policy.
- [Media engine and desktop ownership](issue-46-media-engine.research.md):
  native libwebrtc and RingRTC transport hooks, packaging gaps and video IPC.
- [Candidate comparison](issue-46-media-candidates.research.md): RingRTC,
  LiveKit, native libwebrtc, GStreamer, flutter_webrtc and tgcalls against the
  agreed boundary.
- [Hardware encoding](issue-46-hardware-video.research.md): Discord Go Live's
  GPU path, Telegram's Darwin VideoToolbox path, normal Windows/Linux software
  factories and the limits of tgcalls' unselected direct transport.

Source inspection establishes candidate APIs, not a working Moss media engine.
Native packaging, media protection and real-device quality require a focused
feasibility check before replacing the working voice pipeline.

## Preferred feasibility candidate

RingRTC's low-level Rust WebRTC factory is the first candidate to validate.
It exposes an injected virtual UDP network without requiring Signal's service
or CallManager, while retaining established audio/video processing. Keep its
negotiation format and native pointers behind a Mosh-owned engine adapter.
This is a research recommendation, not an adopted dependency.

Before adoption, prove:

1. Pinned native artifacts link in the existing desktop builds, including
   Windows debug and both macOS architectures. Resolve the mismatched Rust/C++
   callback return declarations rather than assuming ABI compatibility.
2. All engine packets use the selected Moss peer, with bounded queues and
   usable timing/loss feedback. No external ICE server or alternate network path.
3. Authenticated selected-device negotiation installs fresh directional SRTP
   keys. The current public API reconstructs Signal V4 descriptions with DTLS
   disabled; generic SDP/DTLS exchange is not a verified path.
4. Camera input, duplex audio, decoded video and child-window frame delivery
   meet the quality target. Desktop VP8/VP9 factories are software codecs;
   source availability does not establish CPU, battery or thermal behavior.

Mandatory Signal-related dependencies, AGPL-3.0 licensing, toolchain differences
and artifact availability also need explicit review at dependency selection.
GStreamer is the strongest alternative if RingRTC requires substantial private
fork maintenance; it trades direct application packet APIs for more pipeline
composition. Revisit that choice after the focused proof, not by silently
keeping separate permanent audio and video engines.

Record the negotiated codec, encoder implementation and known hardware/software
state from the actual media runtime. Hardware capture or decoding does not prove
hardware encoding. Keep encoder selection inside the engine adapter so an
available hardware path does not require changes to call ownership or Moss.

## Open decisions

- Rules for discovered occupancy conflicts, simultaneous cross-calls and
  competing answer/refusal transitions.
- Camera activation before answer, camera/device changes and minimizing behavior.

## Remaining proof work

- Validate the native candidate, reproducible packaging and directed Moss
  integration, including authenticated media-key exchange and bounded frame IPC.
- Measure relay capacity, choose numeric flow budgets and verify message/audio
  progress under video pressure.
- Execute acceptance scenarios and sustained quality checks on real desktop
  hosts, including permission refusal and receive-only calls.

## Checks and risks

Use existing widget adapters and independent real Moss processes. Preserve the
voice baseline, navigation and window lifecycle while adding video incrementally.
Implementation checks include Flutter analyze/tests/format, Rust tests/fmt/clippy,
and bridge generation/drift checks if native API signatures change.

Primary risks are competing device answers, unauthenticated control messages,
media queue latency, relay capacity, video crossing the desktop process boundary,
and regressions in working voice calls. No production code has changed.
