# Native audio/video calls

Windows, macOS, Linux and Android use one native RingRTC audio/video engine per selected
call. The DM header has voice and video actions. A video start opens local
preview; media is sent only after the caller confirms the answering installation.
An incoming call starts with camera off. Camera and microphone choices are
independent, and permission refusal preserves reception and other capabilities.

The ready desktop call window owns microphone, camera and end controls. The main
strip shows call status and a button to reopen that window. Until the window is
ready, or after a presentation failure, the strip supplies the call controls.
The window adds selectors for microphone, speaker and camera, using `MoshSelect`.
They send commands for the displayed DM/call. Initial audio preferences map
existing Record/CPAL IDs against the engine's current inventory; stale initial
choices use the default. During a call, losing a chosen input disables that
input, preserving video and playback. Losing output returns to default output.
Capture is never reenabled automatically when a device returns. Camera IDs
without a stable platform identity remain scoped to the call.

Sound & Video settings stores a desktop camera default beside microphone and
speaker preferences. When the camera is first enabled, the native owner resolves
that stable ID against its asynchronous helper inventory; an unavailable default
uses the normal default camera. Voice-only preparation never waits for camera
enumeration, and the owner continues audio and device controls while inventory
is pending. A failed inventory refresh retains the last successful camera list
and logs the error; a successful empty result clears it. Per-call camera choices
remain independent and do not overwrite the saved default. Merely opening
settings enumerates devices without opening a stream or preparing an engine.
Only an explicit camera-selection command changes the per-call device ID.
Microphone, speaker and camera on/off commands preserve the native owner's
current ID, so an older presentation snapshot cannot undo asynchronous fallback.

Android ARM64 uses the same authenticated native protocol, virtual Moss network,
codecs and SRTP key agreement as desktop. Its pinned WebRTC source build enables
the native factory (the official Android binary has a null stub) and uses WebRTC's
Android AudioRecord/AudioTrack module. AudioManager selects a communication route
and its paired microphone; independent desktop microphone selection is not an
Android call capability. A stale output pick falls back to the system route.
Camera2 capture publishes one latest RGBA frame through JNI, with generation
checks before and after conversion so callbacks from an old camera cannot revive
capture. Pixel rotation/conversion uses WebRTC/libyuv. Permission is requested
before opening the camera, independently of microphone consent.

The Android call view reuses the shared controls, device dialog and video renderer
inside the app. Back minimizes that view; the chat and native call remain mounted.
A lazy application-owned Flutter engine retains the Dart/native owners when
Android recreates its Activity. Ringtone and PiP configuration outlive the window;
only permission UI and the PiP shield attach to it. See
[Android runtime ownership](android-runtime.md) for checks and physical-device limits.
A dialog receives Back before minimization. Opening the peer returns to its DM;
the compact strip can restore the view. Foreground Android ↔ desktop calls are
the acceptance target. Suspended/killed-app ringing is not implemented by this
change. iOS retains the legacy voice pipeline and cannot answer native offers.
Older Android builds also require an update; incompatible offers still do not ring.

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

Windows launches both capture and camera enumeration with `CREATE_NO_WINDOW`,
so the five-second inventory refresh cannot open a console. A camera busy in
another application can fail the first frame with Media Foundation error
`0xC00D3704`. Closing the other application's capture and enabling the camera
again preserves the existing audio call.

Capture selects an actual supported format near 720p30. macOS patches request
available BGRA output, validate actual pixel-buffer layout, remove row padding,
retain callback sender ownership and quiesce the delegate queue before release.
Failure during stream initialization also removes its delegate. A two-frame
30Hz cadence handles driver jitter without dropping alternate 30Hz frames due
to processing time.

The macOS configuration patch matches resolution and nokhwa's pixel-format descriptor with an
FPS endpoint belonging to that same native format. It uses the original native
frame duration, including fractional rates, and releases the configuration
lock. This corrects a backend loop that could combine a 720p10 format with a
different format's 30 fps duration. The reporter has confirmed working camera
capture on the Mac Mini with the patched universal build. Intermittent remote
video pauses remain a separate delivery/presentation investigation.
Nokhwa normalizes several native FourCC values to one descriptor; diagnostics
retain the native FourCC, while selection keeps each format and duration paired.

The helper reports startup phases, the selected mode and first complete frame
to stderr; macOS also lists up to 64 native modes with actual FPS ranges.
The owner continuously drains stderr, retaining only its final 8 KiB. After
capture stops, the existing application field log records that tail, output
failure or timeout, process exit status and whether the owner terminated it.
Camera startup failures before spawning are logged as well. Enumeration still
discards stderr. Binary stdout frames, account identities and media keys are
never included in these diagnostics.

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
local preview and uses a small secondary preview over remote video. While the
peer's camera remains enabled, an expired or not-yet-received remote frame shows
"Waiting for video…" in the same stage and keeps local preview small. A
camera-state change permits switching back to a local-only stage;
frame expiry does not mean the peer disabled their camera. Fresh frames restore
remote video automatically without retaining an expired image. Frequent
frames and the timer do not animate; discrete icon/stage changes honor reduced
motion. No encoder hardware badge is inferred: diagnostics show the actual
codec/implementation reported by the engine.

The existing application log records native media transitions: route, ICE
connection state, remote video waiting/live/stalled/off, decoded-frame age/count,
packet drops and audio/video codec statistics. Identical states do not repeat.
These events distinguish remote capture failure (camera-off plus the sender's
helper log), interrupted decoding/delivery (stalled), and presentation trouble
while native reception remains live. They contain no images, audio or media keys.
An uninterrupted audio stream alone does not prove the video path is healthy.

## Capacity and recovery

The client limits queued media to 500 ms and gives negotiated audio payloads,
STUN and RTCP priority over video. Short bursts wait for capacity inside that
deadline; both budgets are charged only when the packet can be sent. Waiting
video never blocks newly queued audio/control. The deadline accommodates a maximum
2,027-byte wrapped packet's 63.4 ms refill time on a depleted relay video budget,
with headroom for keyframe bursts and delayed thread wakeups. Eight 1,473-byte
fragments need about 368 ms with no credit, or 268 ms with a full bucket.
The engine packet queue expires packets after 200 ms, so delayed polling does
not discard fresh frame fragments
before they reach the sender. Both queues remain bounded; the one-second decoded
frame freshness limit is unchanged.
Route and encoder limits apply before packets are transferred, independently of
the 250 ms statistics refresh. Unknown routes use relay limits until a direct
path is confirmed. Direct sending allows 500,000 bytes/s total
and 450,000 video. Relayed sending allows 48,000 bytes/s total and 32,000 video;
the engine's relay send-rate ceiling is 224 kbit/s and sends 270p15 on that
path, versus up to 3 Mbit/s and 720p30 on direct paths. Budgets from 300 to
600 kbit/s send 360p15. Below 300 kbit/s a detailed 360p keyframe takes about a
second to send, longer than the renderer's one-second frame expiry. The shared capacity
policy keeps the engine below the carrier's video allowance with room for
packet framing. WebRTC supplies congestion adaptation.
An idle sender waits for a queue notification without a periodic timer.
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
The call window executable (`Contents/MacOS/mosh-call-window`) is signed the same
way; see [voice calls](voice-calls.md).
Windows places the DLL/helper beside the executable; Linux places both in `lib`,
with executable permission on the helper. Do not ship the test camera driver.

```sh
node scripts/native-media-build.mjs
cargo build --manifest-path mosh-core/Cargo.toml --features native-media-tests --lib --bin mosh-camera-test-driver --test device_link_flow
# Set MOSH_MEDIA_ENGINE to the built engine and MOSH_CAMERA_CAPTURE to the
# compiled test driver for reproducible driver-fixture checks.
cargo test --manifest-path mosh-core/Cargo.toml --lib --features native-media-tests native_call:: -- --include-ignored
node scripts/moss-test.mjs --test device_link_flow native_ -- --ignored --nocapture
node scripts/moss-test.mjs --native-call-ui
```

The relay regression allows eight seconds for codec bandwidth adaptation, then
requires at least 30 decoded frames over eight seconds. The first decoded frame
must arrive within three seconds, and subsequent frames must stay fresh within
one second throughout both phases. Capture uses an absolute 15 fps schedule,
skipping missed slots instead of accumulating delay or sending catch-up bursts.

The last command runs one real Flutter app, an independent public-API peer and
its child renderer with a local discovery tracker. It needs a desktop display
and the same native artifact/driver environment. The physical-device acceptance
and current evidence are recorded in
[implementation results](../Proposals/issue-46-native-implementation.results.md).

The packet regression drives the real engine through the production sender with
a controlled relay route and a moving subject over a detailed background. It
requires continuously fresh decoded frames within the renderer's one-second
expiry. Separate checks cover short bursts, audio/control priority, expired
packets and transport refusal. This reproduces carrier-induced video loss;
physical camera discovery and macOS signing still require the affected device.

For a physical-camera failure, close other camera applications and run the
packaged helper directly through the diagnostic command below. It checks a
complete RGBA frame, reports readiness and stderr, and terminates the helper.
It saves no video. Use the helper from the affected build rather than a fixture.

```sh
node scripts/native-camera-check.mjs /path/to/mosh-camera-capture.exe
```

In the reported Windows case, a busy camera failed before its first frame. After
release, the original installed helper produced 261,736,282 bytes in five seconds
without error. An independent Media Foundation probe also received 30 frames in
NV12 720p, MJPEG 720p and YUY2 480p. This does not establish performance on other
cameras; it confirms that the reported capture refusal was device contention.
