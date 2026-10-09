# Desktop audio/video calls

Windows, macOS and Linux use one native RingRTC audio/video engine per selected
call. The DM header has voice and video actions. A video start opens local
preview; media is sent only after the caller confirms the answering installation.
An incoming call starts with camera off. Camera and microphone choices are
independent, and permission refusal preserves reception and other capabilities.

The call window and compact strip have microphone, camera and end controls.
The window adds selectors for microphone, speaker and camera, using `MoshSelect`.
They send commands for the displayed DM/call. Initial audio preferences map
existing Record/CPAL IDs against the engine's current inventory; stale initial
choices use the default. During a call, losing a chosen input disables that
input, preserving video and playback. Losing output returns to default output.
Capture is never reenabled automatically when a device returns. Camera IDs
without a stable platform identity remain scoped to the call.

Android/iOS retain the existing voice pipeline. Authenticated offers identify
the media protocol, so an incompatible installation does not ring or become the
selected receiver. Desktop/mobile calls are currently unsupported; a contact
with a compatible desktop installation can still answer there. All installations
must upgrade together; the call protocol has no older-client compatibility layer.

## Ownership and encryption

`mosh-core/src/native_call` owns the engine, capture helper, device choices,
latest decoded frames and bounded transport queues on a dedicated thread.
The engine's raw handle stays on that thread; no unsafe `Send` wrapper carries
WebRTC objects between bridge threads. Its code library remains loaded until
process exit because native dependencies retain global and thread-local state.
A thread-bound Windows COM apartment guard outlives every endpoint field, so
native audio objects are released before COM uninitialization. Engine teardown
still releases capture, playback and connection resources. Slow Moss sends
run separately, so they cannot block camera off, decoding or device commands.
The native `Owner` is a documented exception to the 200-line type limit so
capture, negotiation and engine lifetimes stay in one thread-bound state machine.

`mosh-media/engine` is a separate Rust dependency graph. RingRTC's mandatory
Signal/hax dependencies conflict with OpenMLS's graph, so they cannot share the
core manifest. The library exposes bounded C commands, binary packets and RGBA.
Its factory owns audio DSP, capture/playback and video processing in one session.

Only public negotiation descriptions cross MLS. Each selected session generates
fresh X25519 material, rejects non-contributory keys and derives directional
SRTP keys with HKDF/SHA-256. The transcript binds the DM, call, selected caller
and receiver leaf signers, fresh media nonce, roles and crypto suite. Private
DH/SRTP keys stay in the engine and are zeroized on teardown. Neither Dart nor
the renderer receives them. Current signed roster removals and MLS membership
are reconciled against the selected pair; loss of authorization clears that
call and releases both media paths. Locally failed/end calls persist their
closed-ID book before media synchronization.

An active selected receiver that gets no media offer fails setup after 15 seconds.
Unit tests check that deadline with controlled instants; process tests allow up
to 30 seconds for DM owners to observe and persist termination over IPC.

A counterpart's device selection can reserve occupancy only for an admitted
offer from that original caller. Its caller binding survives local presentation
dismissal and sibling-selection retries, and confirmed termination clears it.
Authenticated own-sibling occupancy remains independent of a local offer.
After restart, offer evidence is empty, so only own-sibling occupancy can restore
Busy for an ongoing call on another device; counterpart selection alone cannot.

RingRTC receives only a virtual UDP interface. Actual packets use Moss directed
peer packets, with a call nonce and selected-peer check before native decoding.
No engine ICE server or another mandatory server is configured. Moss supplies
its own automatic discovery, NAT traversal and relays.

## Capture and presentation

`mosh-media/capture` is a capture-only helper using pinned nokhwa. It owns one
camera on its capture thread and sends validated RGBA over a bounded binary
pipe. Timestamps use Unix time. The pinned macOS backend converts sensor
monotonic timestamps before constructing its buffer, preserving age through
the pipe. Parent stdin EOF terminates it, even while a driver read blocks.
Camera off disables the native video track and kills/reaps the helper. Four seconds
without frames after readiness fails that capture while preserving the call;
initial camera permission has a separate 65-second startup limit.

Capture selects an actual supported format near 720p30. macOS patches request
available BGRA output, validate actual pixel-buffer layout, remove row padding,
retain callback sender ownership and quiesce the delegate queue before release.
Failure during stream initialization also removes its delegate. A two-frame
30Hz cadence handles driver jitter without dropping alternate 30Hz frames due
to processing time.

`NativeCallSession` in Dart owns commands and presentation polling. Rust retains
media when this client or the window disappears. The child window starts no
Rust, capture or audio runtime. Public state travels through inherited stdio;
frames use a dedicated loopback socket with a one-time 256-bit capability.
Only one frame is in flight. Missing acknowledgement closes that renderer after
five seconds; the main strip can restore it. Stream and write failures are both
handled, including a TCP reset during a frame write.

Each lane retains its latest image, and the renderer has one decode in flight.
Call/generation checks discard old responses, and image age includes transfer
and decode time. Images expire after one second without fresh delivery. Camera
off clears its image immediately. Rendering preserves aspect ratio, mirrors
local preview and uses a small secondary preview over remote video. Frequent
frames and the timer do not animate; discrete icon/stage changes honor reduced
motion. No encoder hardware badge is inferred: diagnostics show the actual
codec/implementation reported by the engine.

## Capacity and recovery

The client limits queued media to 50 ms and gives negotiated audio payloads,
STUN and RTCP priority over video. Direct sending allows 500,000 bytes/s total
and 450,000 video. Relayed sending allows 48,000 bytes/s total and 32,000 video;
the engine caps video at 320 kbit/s and adapts to 360p15 on that path, versus
up to 3 Mbit/s and 720p30 on direct paths. WebRTC supplies congestion adaptation.
Every observed connection loss receives a fresh 15-second recovery window.
After that, local termination clears capture and persists the terminal state.

These are client flow limits. The unchanged Moss relay still lacks an aggregate
node budget and audio/message reservations. Its injectable-network sender
acknowledges enqueueing, not final socket completion. Those adoption gates remain
open; raising a per-peer allowance alone does not solve them.

## Build and checks

Desktop Flutter builds run `node scripts/native-media-build.mjs` through the
native plugin/Xcode hook. It prepares verified source archives and patches,
builds both isolated crates and packages the library/helper and license notices.
An explicit/system `protoc` is accepted; otherwise the hook downloads a locally
scoped, SHA-256-verified protoc 36.2. Windows builds need Visual Studio's desktop
C++ tools, Rust, Flutter and Node; no global protobuf installation is required.
macOS also needs `brew install coreutils` for RingRTC's GNU realpath downloader,
alongside the existing autoconf/automake/libtool build prerequisites.

macOS builds each requested architecture and uses `lipo` for universal output.
The engine is signed as a framework; the helper inherits the main app sandbox
and carries camera usage text. The main app owns microphone/camera permissions.
DMG packaging verifies the helper's architectures and re-signs it with its
sandbox inheritance entitlements before sealing the application.
Windows places the DLL/helper beside the executable; Linux places both in `lib`,
with executable permission on the helper. Do not ship the test camera driver.

```sh
node scripts/native-media-build.mjs
cargo build --manifest-path mosh-core/Cargo.toml --features native-media-tests --lib --bin mosh-camera-test-driver --test device_link_flow
# Set MOSH_MEDIA_ENGINE to the built engine and MOSH_CAMERA_CAPTURE to the
# compiled test driver for reproducible driver-fixture checks.
node scripts/moss-test.mjs --test device_link_flow native_ -- --ignored --nocapture
node scripts/moss-test.mjs --native-call-ui
```

The last command runs one real Flutter app, an independent public-API peer and
its child renderer with a local discovery tracker. It needs a desktop display
and the same native artifact/driver environment. The physical-device acceptance
and current evidence are recorded in
[implementation results](../Proposals/issue-46-native-implementation.results.md).
