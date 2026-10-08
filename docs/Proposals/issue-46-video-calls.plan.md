# Issue 46: video calls between contacts

Product and ownership decisions agreed on 2026-10-08 through questions Q1–Q21
for [issue 46](https://github.com/redstone-md/mosh-flutter/issues/46). This is the
implementation plan, not a report of implemented video support. Engine adoption,
transport budgets and desktop quality remain subject to the proof gates below.

## Agreed requirements

- Start a call from a private DM; the contact can accept or decline.
- macOS and Windows require full acceptance testing. Preserve Linux behavior
  and verify it with available tooling. Android and iOS follow later.
- All call media uses Moss, including direct and relayed paths. Reuse its
  discovery and NAT traversal; add Moss capabilities when needed. No new
  mandatory server infrastructure. Engine adoption depends on the proof gates.
- Ring the contact's available linked devices. An answer selects one receiving
  device; other devices stop ringing. See [ADR 0043](../ADR/0043-one-device-per-user-in-a-call.md).
- Explicit decline on one receiving device ends the pending call on all devices,
  unless the caller has already confirmed another device's answer.
- Occupancy belongs to the user. A pending outgoing or admitted incoming call
  reserves it through ringing, setup, active media and reconnection. A free sibling
  cannot admit an unrelated call while that occupancy is known.
- A remaining reachable device can call without permission from unavailable
  siblings. User-wide occupancy is best effort during network partitions;
  different devices can temporarily hold overlapping calls. Discovering the
  conflict preserves existing calls, informs the user and blocks new calls until
  all calls involved have ended. Do not terminate an active call automatically.
- Simultaneous calls between the same two users merge into one call before media
  starts. Preserve each user's chosen microphone and camera states.
- The caller arbitrates answer/refusal races. Its first confirmed transition
  wins; a stale refusal from another device cannot end an accepted call. Only
  the selected participating devices may terminate an accepted call.
- Audio and video belong to one call. Either participant can enable or disable
  their camera during a voice or video call without starting another call.
- Accepting a call does not automatically enable the receiving camera. Camera
  permission refusal preserves voice calling.
- Starting a video call opens a local preview. Send media only after the answer
  and participating devices are confirmed. Turning the camera off stops capture
  and releases the device; minimizing preserves the selected microphone/camera
  states.
- A missing or refused microphone does not prevent receiving audio/video.
  Show its unavailable state and allow enabling a working microphone later.
- Device selection belongs in the call window. Initial audio choices reuse the
  existing audio settings. Losing a device preserves other media capabilities;
  reconnecting it must not re-enable a camera or microphone the user disabled.
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
- Use `interface-design` for the call interface and `transitions-dev` for motion.
  Reuse the current Flutter theme and components. See the
  [interface and motion brief](issue-46-call-interface.design.md).

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

## Call coordination

Call identity, the originating DM, selected device identities and a call-bound
transition revision belong to the native call owner. Authenticate controls and
occupancy updates using the existing linked-device identity model. Admission
must use current native state; presentation snapshots cannot select a device,
grant capture consent or revive an ended call.

| Event | Required result |
| --- | --- |
| Contact has several reachable devices | Ring each available device; one answer can select one receiver. |
| Two devices answer | Caller confirms one selection; the other stops ringing and never starts media. |
| Answer competes with decline | First caller-confirmed transition wins; requesting an answer locally is still pending. |
| Decline arrives after selection | Ignore a nonparticipating device's stale refusal; keep the accepted call. |
| Same users call each other before media | Converge on one call and one caller authority; preserve both users' capture choices. |
| An unrelated call arrives during known occupancy | Refuse admission without replacing the current call. |
| Unavailable sibling cannot report occupancy | Reachable device may admit a call; do not wait for a quorum. |
| Partition heals and reveals different calls | Preserve existing calls, show the conflict, block new admission until all involved calls end. |
| Old or duplicate control arrives | Apply it idempotently to its call/revision or discard it; never change a replacement call. |

Cross-call merging needs a deterministic ordering of the authenticated offers
so both devices choose the same call and caller authority. Bind superseded IDs
to that merge and distinguish obsolete controls from a user's current cancel
or end action. Merging must not revive an offer already ended by its user. This
is a protocol implementation detail; it does not permit merging already active
calls or adding a second participating device. A fresh user action after
termination creates a new call rather than reviving an old offer.

Occupancy is a set of known call reservations during conflict recovery. A local
end does not clear another installation's reservation. Synchronize authenticated
current state when linked devices reconnect; a stale cached reservation must not
hold the user busy indefinitely. Unknown sibling state remains subject to the
agreed availability policy, not a strict account-wide guarantee.

## Incremental implementation

Each stage must work end to end before adding the next. Keep the current voice
baseline usable while validating the replacement. Once adopted, one engine owns
both audio and video; the existing pipeline is not a permanent second engine.

1. **Prove the engine boundary.** Use an isolated native probe to establish the
   four adoption gates above. Pin artifacts and document build inputs and any
   upstream patches. Record a go/no-go result before adopting a dependency in
   Mosh. If the boundary fails, compare the documented alternatives at the same
   gates rather than carrying a partial integration into the product.
2. **Coordinate selected devices.** Implement authenticated controls, caller
   confirmation, cross-call merging and linked-device occupancy with current
   voice media. Exercise multi-installation races and partition recovery before
   admitting video. Keep engine-specific negotiation private to the adapter.
3. **Move voice through the native engine.** Establish directed Moss transport,
   media protection, duplex audio, mute, receive-only operation and teardown.
   Preserve settings, navigation, ringing, close/minimize and window recovery.
   Compare real audio behavior with the existing baseline before switching it.
4. **Add video on a direct path.** Add capture/preview, consent, decoded frames
   and bounded child-window delivery. Verify two real desktop peers can answer,
   hear and see each other, turn cameras off, change devices and keep messaging.
   The main process owns capture and keys; dropping the renderer loses frames,
   not the call.
5. **Prove relay quality.** Add required Moss capacity, scheduling and packet
   feedback capabilities at the library boundary. Negotiate bounded flow
   allowances, reserve messages/control and prioritize audio. Measure actual
   overhead, reduce/pause video on constrained routes and validate the 15-second
   recovery limit. Do not substitute bigger buffers for capacity.
6. **Finish desktop acceptance.** Apply the shared interface and motion brief,
   localization, permissions and accessible states. Run the matrix below on
   macOS and Windows; preserve and check Linux. Record sustained quality and
   actual encoder state before calling issue 46 complete.

Dependency, public bridge and protocol changes must be concrete and reviewable
before their required repository approval. Moss extension work is authorized by
the user; it is a separate library change with its own checks and pinned update.
No such changes are made by this design-document task.

## Acceptance matrix

| Scenario | Evidence required |
| --- | --- |
| Two real installations, direct and relay | Bidirectional audio/video; media packets confined to Moss; selected-device authentication and protection. |
| Several linked receiving devices | Ring all reachable devices; two answers select one; accept/decline races follow caller confirmation. |
| Simultaneous cross-calls | One call before media; no repeated ringing loop; both users' microphone/camera choices retained. |
| Busy and partition recovery | Known occupancy blocks another DM call; isolated reachable device can call; discovered conflict preserves calls and blocks new admission. |
| Camera/microphone permissions and hot-unplug | Independent sending/receiving remains available; unavailable state is truthful; explicit disabled state survives reconnection. |
| Camera activation and teardown | Local preview before answer; no outgoing media before confirmation; off releases capture; repeated calls leave no capture owner behind. |
| Navigation, resize, minimize and child failure | Messaging stays usable; minimize preserves capture state; renderer crash preserves audio/call controls; restore recreates presentation. |
| Weak route and reconnect | Audio/messages/control progress under video pressure; adaptive video; recovery succeeds within 15 seconds or call ends. |
| Sustained 720p30 on a sufficient path | Report achieved frames, bitrate, loss, latency, A/V skew, queue/frame age, CPU, thermal behavior and UI responsiveness for the actual host/codec. |
| UI and motion | Keyboard/focus/tooltips, text scaling, long names, narrow window, reduced motion and dark-theme contrast verified visually and with focused widget tests. |

Record host model, OS, architecture, capture/output devices, engine/artifact pin,
route type and test duration with native results. Physical-camera/microphone and
speaker checks on macOS and Windows are required; Linux virtual devices provide
additional coverage rather than replacing those checks. Ringing retains the
existing 30-second no-answer timeout. Existing close/Escape behavior remains
decline, cancel or hang up according to the call phase.

## Remaining proof work

The [native feasibility results](issue-46-native-media.results.md) record the
implemented Linux tracer bullet and outstanding adoption gates. Application
video calls are not implemented by that probe.

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
Prepare Moss before native runtime tests. Use regression tests for existing
caller-visible bugs and the repository's changed-code coverage thresholds.

Primary risks are competing device answers, unauthenticated control messages,
media queue latency, relay capacity, video crossing the desktop process boundary,
and regressions in working voice calls. User-wide busy remains best effort
under partition by design. The current implementation adds an isolated probe
and directed Moss wrappers; the application's call pipeline has not switched.
