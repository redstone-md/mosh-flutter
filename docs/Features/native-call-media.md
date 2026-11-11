# Native audio/video calls

Windows, macOS, Linux and Android use one native libwebrtc audio/video engine per
selected call. The DM header has voice and video actions. A video start opens local
preview; media is sent only after the caller confirms the answering installation.
An incoming call starts with camera off. Camera and microphone choices are
independent, and permission refusal preserves reception and other capabilities.

On Linux the call shows in the main window and its video in two Rust-fed
textures ([ADR 0052](../ADR/0052-desktop-calls-in-the-main-window.md), see
[Main-window textures](#main-window-textures)). Windows and macOS keep the call
window until MOSH-94 and MOSH-95: there, the
ready desktop call window owns microphone, camera and end controls. The main
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
codecs and DTLS-SRTP as desktop. It links the Android build of the same libwebrtc
and uses its AudioRecord/AudioTrack module. AudioManager selects a communication route
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
change. iOS has no call engine yet (MOSH-77): it reports the earlier media
protocol, so a call between it and another device ends asking to update Mosh.
Older Android builds also require an update; incompatible offers still do not ring.

## Engine and media protocol

The engine (`mosh-media/webrtc`, epic MOSH-70) implements the `mosh_media_*`
ABI that mosh-core loads: Google's libwebrtc through LiveKit's bindings,
linked against [our libwebrtc build](../../third_party/libwebrtc-build/README.md)
without its software H.264 (OpenH264, FFmpeg). Its media is
DTLS-SRTP with the certificate fingerprint inside the MLS-authenticated
description ([ADR 0051](../ADR/0051-dtls-srtp-with-mls-authenticated-fingerprints.md)),
its packets cross the same virtual network over Moss, and it sends 20 ms
Opus with RED and without DTX, so a single lost packet costs no audio. On
the bench that concealed 0.4 % of audio at 5 % loss and 1.3 % at 15 %, for
about 21 kbit/s and 50 packets/s; DTX cost RED most of that gain and 40 ms
packets added delay ([measurements](../Proposals/call-engine-without-ringrtc.research.md#measurements)).
Echo cancellation,
noise suppression and gain control are libwebrtc's own. The engine starts
the microphone itself whenever it is switched on: libwebrtc asks for
recording once, when the call connects, and that request is lost while the
microphone is off. A device change restarts a running device, so only a new
input or output pick selects devices; the microphone and camera switches leave
them running. "System default" is Windows' default communication device, not
the first endpoint.
The offer leaves the legacy offerToReceiveAudio unset: the bindings' default
of false made it send-only, so the callee was never heard. The call log
records when the microphone starts or stops capturing sound, when the peer's
audio starts or stops arriving, and the selected devices.

Video in that engine takes the same RGBA camera frames and returns the
peer's latest decoded frame as RGBA, so mosh-core, the capture helper and
the call window are unchanged. Frames enter libwebrtc as I420; the send
budget sets the sender's frame-rate limit and downscale (720p30 direct,
360p15 between 300 and 600 kbit/s, 270p15 relayed, measured on the
frame's shorter side so portrait cameras fit the same box), and
libwebrtc's congestion control degrades from there. A camera that is off
pauses the sender, so a voice call sends no video at all (LiveKit's video
source would otherwise feed black frames until the first camera frame).
Codecs are ranked per call: whatever this device encodes in hardware
(VideoToolbox on Apple, MediaCodec on Android, VAAPI or NVENC on Linux
when present), then VP9, then the rest; negotiation keeps the first one
both sides can send and receive. The Android and Apple hardware factories
also list their software VP8, VP9 and AV1, so only codecs without a
software encoder rank first: in practice H.264 and H.265, which our
libwebrtc encodes only in hardware. A negotiated VP9 or AV1 still encodes
in hardware where the device has it, since libwebrtc tries the hardware
factory before software. Two Macs should therefore use hardware
H.264 and a Mac with a Windows PC VP9; the macOS CI job runs whatever
VideoToolbox offers its runner, the Linux and Windows jobs VP9. On the relay
regression VP9 sends 480x270 at 15 fps and decodes about 120 frames in the
measured eight seconds without loss, where VP8 dropped to 360x198. The call log's `encoder` statistics report the
codec, its implementation and whether it is hardware.
On Android the app
loads the engine from Java (`MoshEngine.kt`) so libwebrtc's JNI code finds
its classes.

The engine reports its media protocol (2; the engine before it spoke 1)
and every call control carries the sender's, absent meaning 1. A build whose
engine fails to load, iOS included until MOSH-77, speaks 0, so it rings
neither an older client nor a current one. Engines on different
protocols cannot connect media, so a callee refuses such an offer instead
of ringing, a caller ends the call when such a device answers, and both
record an "update Mosh" call event (`update_required`) in the chat. A
refusal leaves the contact's other devices ringing (ADR 0043 stops them only
for an explicit refusal); if none answers, the caller's call ends asking to
update Mosh rather than as unanswered. Clients from before this protocol
treat the refusal as a decline. An offer from such a client still carries
its own media keys; they are ignored.

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
A control does not wait for the owner to apply it: the bridge hands over the
choices once it holds the call state and returns, and the snapshot shows what
was asked at once. The outcome, such as a refused microphone, follows in the
snapshot after the owner's next step. The owner steps a working copy of the
call state: it holds the shared lock only to take what the app asked for and to
publish the step's outcome, so a control never waits out an engine or Moss call.
Choices the app makes during a step stay; the next step applies them.
The native `Owner` is a documented exception to the 200-line type limit so
capture, negotiation and engine lifetimes stay in one thread-bound state machine.

`mosh-media/webrtc` is a separate Rust dependency graph, loaded as its own
library, so libwebrtc's C++ build and global state stay out of the core
manifest. The library exposes bounded C commands, binary packets and RGBA.
Its factory owns audio DSP, capture/playback and video processing in one session.

Only public negotiation descriptions cross MLS. Media is DTLS-SRTP, and the
certificate fingerprint travels inside the MLS-authenticated description, so
only the selected device can complete the handshake
([ADR 0051](../ADR/0051-dtls-srtp-with-mls-authenticated-fingerprints.md)).
DTLS and SRTP keys stay in the engine; neither Dart nor the renderer receives
them. Current signed roster removals and MLS membership
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

libwebrtc receives only a virtual UDP interface. Actual packets use Moss directed
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

Frames leave Rust at the size they are shown, not as full camera RGBA. The
video stage dispatches `CallVideoSurfaces` whenever its layout changes: the
device pixels of the remote stage and of the preview (a quarter-width inset
over remote video, else the whole stage). The call window sends them over its
pipe (`call-video-surfaces`), Android's host takes them directly, and the
native call owner passes them to `show_video_at`. The engine scales decoded
I420 down with libyuv before its RGBA conversion (the `surface` command), and
the local preview goes through the engine's stateless libyuv scaler
(`mosh_media_scale_rgba`) before the owner takes the call state lock, fitted
to the surface of the previous step. Both keep the aspect ratio
and never enlarge; until a surface is reported frames stay whole. The encoder
still takes the full camera frame.

### Main-window textures

On Linux no pixel passes through flutter_rust_bridge or Dart. The runner
registers two `FlPixelBufferTexture`s (`linux/runner/call_video_texture.cc`),
local and remote, on the first request over the `mosh/call-video` channel and
keeps them for the process. Each exports one function, `present`, which copies
an RGBA frame and marks the texture's frame available; a frame the raster thread
has not taken yet is overwritten. Dart passes the two export addresses to Rust
with `show_video_in` once a call is prepared. From then on the owner writes
every frame of a lane into its texture at the surface size, `frame` returns
nothing for that lane, and Dart polls no frames. The snapshot's `local_video`
and `remote_video` report the size of the frame each lane shows, zero when
there is none or no newer one followed for five seconds; the stage shows the `Texture` at that
shape and hides it otherwise. The call view lives in the main window: expanded
it covers the content below the title bar and can switch the window to full
screen, minimized it is a strip or, with video, a mini view over the chats. An
incoming call rings in the mini view.

On the Linux host a 720p frame costs about 0.5 ms of CPU to show: 0.39 ms for
the engine's I420 to RGBA conversion and 0.12 ms for the copy into the texture
([call video benchmark](call-video-benchmark.md), 2026-11-11). The bridge and
call window rows it replaces took 8.2 ms and 10.4 ms in the same run.

The rest of this section describes the frame path of the other platforms.

Each lane retains its latest image, and the renderer has one decode in flight.
Call/generation checks discard old responses, and image age includes transfer
and decode time. A pause in delivery freezes the last image, as Meet and Zoom
do; it expires only after five seconds without fresh delivery, and a frame
already that old is never drawn (`CallVideoFrame.lifetimeMs`, shared by the
main process filter and the renderer). The log's `stalled` state keeps its
one-second meaning, so short pauses still show in field logs. Camera off, call
end and a call change clear the image immediately. Rendering preserves aspect ratio, mirrors
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
The engine packet queue holds 32 audio and control packets ahead of 96 video
packets and expires them after 200 ms. A dedicated packet thread carries both
directions every 2 ms, without the call state or engine locks: it drains that
queue straight into the sender and hands inbound Moss packets for this call's
peer and nonce to the engine's virtual network. A slow owner step (camera
frames, statistics, device enumeration) therefore neither ages fresh frame
fragments out nor delivers inbound media in bursts, which would grow the
receiver's jitter buffers. Both queues remain bounded; the one-second decoded
frame freshness limit is unchanged.

The `native media:` log line reports `engine_dropped` as `full` (queue refused
a packet) and `stale` (older than 200 ms when drained). `stalls_max_ms` holds
the longest pauses since the previous line: `step` (one owner step) and its
phases `capture` (camera inventory and capture, with the frame handed to the
engine), `choices` (applying the microphone and camera switches and a new
device pick), `statistics` (engine snapshot and device refresh), `tick` (ICE
candidates and libwebrtc's statistics) and `present` (copying the peer's frame);
`lock_wait` (the owner waiting for the call state lock, which Dart's commands
and frame reads also take) and `drain` (between two passes of the packet
thread; about 2 ms is the baseline). The thread only sleeps and copies, so a
`drain` far above that points at the process not getting CPU time. Whatever
`step` holds beyond its phases went to call negotiation. The `video` and `audio` metrics include
`jitter_buffer_ms`, the average wait before playout. While the engine or the
sender keeps dropping, the line repeats every 10 seconds even if the call
status holds.
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
Every observed connection loss receives a fresh 30-second recovery window,
and the call shows "Reconnecting" meanwhile. After that, local termination
clears capture and persists the terminal state (`connection_lost`).

ICE reports Disconnected after about 5 seconds without packets and Failed
after about 15, and a failed path never comes back on its own. When the
caller's ICE fails, the caller restarts it: a new offer with fresh ICE
credentials goes over the call signaling and is resent every second until
the call is connected again, while the call, its tracks and DTLS stay. The
callee answers every offer it receives, even while its own side of the path
still looks connected. Only the caller
restarts, so the two sides never restart at once; a restart that fails again
is followed by another within the same window. Descriptions arrive late or
twice, so each side takes only one with a newer SDP session version than the
last it accepted, and the caller takes a new answer only for its pending
restart. A peer on an older build cannot answer a restart; its call ends as
before. The memory-network regression cuts a call until both sides fail,
restores the path, and requires the same call to be media-ready again.

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
Linux needs `CC`/`CXX` set to clang 21 or later for libwebrtc's hermetic
libc++.

macOS builds each requested architecture and uses `lipo` for universal output.
The engine is signed as a framework; the helper inherits the main app sandbox
and carries camera usage text. The main app owns microphone/camera permissions.
DMG packaging verifies the helper's architectures and re-signs it with its
sandbox inheritance entitlements before sealing the application.
The call window executable (`Contents/MacOS/mosh-call-window`) is signed the same
way; see [voice calls](voice-calls.md).
Windows places the DLL/helper beside the executable; Linux places both in `lib`,
with executable permission on the helper. Do not ship the test camera driver.

CI runs one native call media job per OS: lint and the engine and camera
helper tests, the relay video regression, call setup and the camera tests
through mosh-core over real Moss, and on Linux a voice call between
PulseAudio devices over two Moss nodes, heard in both directions, with the
microphone on from the start and switched on only after connecting
(`scripts/webrtc-voice-check.mjs`). A separate job builds a debug Android
arm64 APK. The frame path's cost is measured apart from CI's checks; see
[call video benchmark](call-video-benchmark.md).

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

The last command runs one real Flutter app and an independent public-API peer
with a local discovery tracker. On Linux the call shows in the main window
(`integration_test/native_call_main_window_test.dart`), which also mutes a live
microphone and so needs an audio input; elsewhere the app starts its child
renderer (`integration_test/native_call_test.dart`). It needs a desktop display
and the same native artifact/driver environment. The physical-device acceptance
and current evidence are recorded in
[implementation results](../Proposals/issue-46-native-implementation.results.md).

The packet regression drives the real engine through the production sender with
a controlled relay route and a moving subject over a detailed background. It
requires continuously fresh decoded frames within the renderer's one-second
expiry. Separate checks cover short bursts, audio/control priority, expired
packets and transport refusal. This reproduces carrier-induced video loss;
physical camera discovery and macOS signing still require the affected device.
Two stall regressions let the owner pause in real time: outgoing video keeps
under 1% loss before Moss, and inbound video's jitter buffer stays at its
no-stall level instead of growing to about 230 ms.

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
