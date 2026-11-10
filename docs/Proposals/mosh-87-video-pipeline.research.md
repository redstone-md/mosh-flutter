# MOSH-87: video pipeline without RGBA copies

Research date: 2026-11-10, on `docs/video-pipeline` (cut from 0.28.2). Sources are
this repository, the pinned dependency sources it builds from, the Flutter 3.44.7
engine source (framework commit `84fc5cbb22`), and Apple, Microsoft, Khronos/ANGLE
and kernel documentation. Every number below was measured on a Linux x86_64 host
(AMD EPYC 7713 KVM guest, 16 vCPU at 2.0 GHz) unless it is explicitly marked as an
estimate or a field report. Mac and Windows numbers must be remeasured on devices;
the [open questions](#open-questions-requiring-a-mac-or-windows-device) say how.

Decision (2026-11-10): the owner chose to present desktop calls in the main window
with a Rust-fed texture instead of keeping the child process
([ADR 0052](../ADR/0052-desktop-calls-in-the-main-window.md)). Steps 2 to 4 below
describe the rejected child-process variant; their measurements still apply.

## Summary recommendation

Both structural costs are real, and the biggest ones are not memcpys. On this host a
remote 720p frame costs at least 26 ms of CPU between decoder and screen, mostly
flutter_rust_bridge's per-byte serialization and the Dart socket path; the camera path
adds 10 to 16 ms per frame. Both Dart UI isolates, which also run the call controls,
carry that pixel work.

Do these steps in order. Build costs are engineering estimates; savings are host
measurements per 720p frame at 30 fps, expressed as a share of one host core.

| # | Step | Build | Expected saving (host) |
|---|------|-------|------------------------|
| 1 | Control path: toggles stop restarting audio devices, stop blocking on the owner step, show pending state at once | 2 to 3 days | No CPU; removes the multi-second toggle stall |
| 2 | Pixels never enter Dart or flutter_rust_bridge: Rust writes the latest frame into a shared-memory slot, a native texture in the call window shows it. Linux first as the tracer | 4 to 5 days | About 25.7 ms of 26.3+ ms per remote frame, about 77% of a core at 30 fps, plus the local lane |
| 3 | Same texture on macOS (IOSurface-backed `CVPixelBuffer` filled from the slot) | 3 to 4 days | Same as step 2 on the field platform |
| 4 | Same texture on Windows (pixel-buffer texture over a named file mapping) | 3 to 4 days | Same as step 2 |
| 5 | Camera helper sends native YUV (420v/NV12/YUYV; MJPEG decoded to planar YUV), the engine encodes without RGBA | 4 to 6 days | 9 to 11 ms per frame on the macOS path (27 to 33%), about 8 ms on the MJPEG path (24%), plus the AVFoundation BGRA conversion the host cannot measure |

Keep the separate call-window process for now. Moving presentation into the engine
process is the right end state, but on stable Flutter it needs either the windowing
API that Flutter itself marks experimental and not for production, or a second
Flutter engine with hand-written window hosting on three platforms. Steps 2 to 4
remove the cost that motivates the move without that risk, and every piece except
the shared-memory slot survives it. Retire the process (ticket 7) once Flutter's
multi-window support ships on stable; the texture plugin and the Rust frame slot
then move unchanged into a second view of the main engine.

Cross-process GPU sharing (IOSurface mach ports, DXGI handles, dmabuf) would save at
most one 720p memcpy (about 0.15 ms) over shared memory, since decoded frames on
Windows and Linux are CPU buffers anyway; not worth the macOS sandbox work below.

## Current pipeline

### Capture to encoder

macOS (the Mac mini path; the log's `YUYV Format` is nokhwa's descriptor for the
native `420v`/`yuvs` FourCCs, see `third_party/nokhwa-macos/src/lib.rs:404-414`):

1. AVFoundation converts the camera's native 420v/yuvs buffer to 32BGRA, because the
   patched binding always requests BGRA output (`third_party/nokhwa-macos/src/lib.rs:2401-2425`).
   Apple's guidance is the opposite: "Avoid defaulting to a BGRA format, because BGRA
   formats aren't native and require conversion", about 2.6 times the memory of 420v
   ([AVCaptureVideoDataOutput][avf-output], [TN3121][tn3121]).
2. The callback copies BGRA into packed 24-bit RGB, pixel by pixel
   (`third_party/nokhwa-macos/src/lib.rs:471-475`, `packed_bgra.rs:2-22`).
3. `Buffer::with_timestamp` copies that again (`lib.rs:515-516`, nokhwa-core 0.1.9
   `buffer.rs:55-67`).
4. `decode_image::<RgbAFormat>` expands RAWRGB to RGBA through an iterator
   (`mosh-media/capture/src/main.rs:124-127`, nokhwa-core `pixel_format.rs:160-163`).
5. The helper writes 3.7 MB per 720p frame to stdout (`main.rs:140,148-162`).
6. The core reads it into a fresh zeroed `Vec` (`mosh-core/src/native_call/capture/desktop.rs:188-189`).
7. The preview is fitted with `scale_rgba`, which converts the whole RGBA frame to I420,
   scales, and converts back (`capture.rs:48-49`, `library.rs:297-345`,
   `mosh-media/webrtc/src/camera.rs:102-110`); when it already fits, it is cloned
   (`capture.rs:57`).
8. The encoder push converts RGBA to I420 under both the call-state and engine locks
   (`capture.rs:72-74`, `mosh-media/webrtc/src/abi.rs:161-183`, `video.rs:110-128,196-212`).
9. With H.264 on VideoToolbox, the I420 frame is copied into an NV12 `CVPixelBuffer`
   (libwebrtc m150 `sdk/objc/components/video_codec/RTCVideoEncoderH264.mm:563-575`); a
   native `CVPixelBuffer` input would be passed through instead (`:529-539`).

Windows and Linux skip steps 1 to 3: nokhwa delivers the native MJPEG, YUYV or NV12
buffer (Windows disables Media Foundation converters,
nokhwa-bindings-windows 0.4.6 `src/lib.rs:470`) and step 4 decodes it to RGBA
(mozjpeg for MJPEG, scalar Rust for YUYV/NV12; nokhwa-core `types.rs:1456,1603,1729`).
`formats::choose` ignores compression (`mosh-media/capture/src/formats.rs:14,20-28`),
so a USB 2.0 camera at 720p30 is MJPEG in practice: uncompressed YUYV needs
55 MB/s, while a high-bandwidth isochronous endpoint carries at most three 1024-byte
transactions per 125 µs microframe, 24.6 MB/s (USB 2.0 specification, section 5.9).
That same limit means the Mac mini's USB camera most likely sends MJPEG on the wire
and macOS decodes it before Mosh sees 420v/yuvs; Mosh's own code does no MJPEG work
on macOS. Where that system decode is accounted is an open question.

### Decoder to screen (remote lane)

1. The engine scales the decoded frame to the surface in I420 and converts it to RGBA
   in its spare buffer (`mosh-media/webrtc/src/frames.rs:86-107`). VideoToolbox H.264
   output is an IOSurface-backed NV12 `CVPixelBuffer`
   (libwebrtc m150 `RTCVideoDecoderH264.mm:241-261`), converted to I420 first.
2. `copy_frame` copies it out under the engine lock (`frames.rs:169`, `abi.rs:190-223`,
   called from `mosh-core/src/native_call/connection.rs:185`).
3. `.to_vec()` copies it into a new `Frame` under the call-state lock (`connection.rs:189-196`).
4. `Hub::frame` clones the whole frame for every poll (`mosh-core/src/native_call/mod.rs:203`).
5. flutter_rust_bridge's SSE codec serializes `Vec<u8>` one `write_u8` per byte into a
   growing `Cursor<Vec<u8>>` (`mosh-core/src/frb_generated.rs:11785-11793,12810-12814`).
6. Dart copies the external buffer with `Uint8List.fromList` (`lib/src/rust/frb_generated.dart:7646-7650`,
   flutter_rust_bridge 2.12.0 `read_buffer.dart:100-108`).
7. `CallVideoFrame.encode` copies into a new packet (`call_video_frame.dart:64-71`).
8. The packet goes into the loopback socket (`call_window_frame_channel.dart:75`).
9. The child reassembles socket chunks into a new body (`call_window_input.dart:102,117`).
10. `ImmutableBuffer.fromUint8List` copies again (`call_video_renderer.dart:119`).
11. `ImageDescriptor.raw` and `instantiateCodec` create the image (`call_video_renderer.dart:123-128`),
    followed by the GPU upload.

That is two colour conversions, eight user-space copies, two kernel copies and the
upload; the local lane takes the capture preview (step 7 above) through steps 3 to 11. Dart polls every 16 ms and pulls frames before it knows whether the window
can accept one: `ProcessCallWindow.presentFrame` drops frames while the previous one
is unacknowledged (`process_call_window.dart:133-140`) and the coordinator drops them
while a state update is in flight (`call_window_coordinator.dart:68-81`), after steps
2 to 6 have already run (`native_call_session.dart:150-196`).

Remote frames never exceed 1280x720: the sender caps at 720p (`video.rs:32-47`) and
surfaces never enlarge (`frames.rs:36-45`); the 1920x1080 cap (`library.rs:16`) only
matters for the local lane. The Mac mini log of 2026-11-09 shows it does: the helper
selected `1280x720@30FPS` yet wrote its first frame at 1920x1080, so on that camera
the local preview can carry 8 MB frames at full screen (open question 8).

## Camera path findings

The engine already has what a YUV path needs. The pinned libwebrtc crate exposes
`NV12Buffer`, `I420Buffer`, `nv12_to_i420`, `i422_to_i420`, and `NativeBuffer` from a
`CVPixelBufferRef` or a dmabuf (`third_party/libwebrtc/src/video_frame.rs:526-561,580-640`,
`native/yuv_helper.rs`). `capture_frame` accepts any buffer type and only converts
when it must (`third_party/webrtc-sys/src/video_track.cpp:189-257`).

- macOS. Request 420v from `AVCaptureVideoDataOutput` instead of BGRA, or an empty
  `videoSettings` for the device-native format ([videoSettings][avf-settings]); TN3121
  lists 420v/420f as native. The helper then forwards the two planes. This removes
  steps 1 to 4 and 7 to 8, cuts pipe bytes from 3.69 MB to 1.38 MB per 720p frame, and
  leaves one NV12 to NV12 copy into VideoToolbox's pool. Zero-copy into the encoder
  (`NativeBuffer::from_cv_pixel_buffer`) would need the capture inside the engine
  process or an IOSurface handoff from the helper; it would save about 0.1 ms per
  frame and is not worth giving up the helper's isolation.
- Windows. Keep native types. NV12 and YUY2 cameras convert to I420 with libyuv in
  0.06 and 0.08 ms at 720p. MJPEG needs a decoder: mozjpeg's raw planar output costs
  6.1 ms against 11.9 ms for RGBA. Media Foundation can also insert its MJPEG decoder
  when asked for an uncompressed output type ([Source Reader][mf-reader]); nokhwa
  disables that today. Decoding stays in the helper so untrusted JPEG parsing stays out
  of the main process.
- Linux. Same as Windows through V4L2. `VIDIOC_EXPBUF` can export capture buffers as
  dmabuf ([kernel][v4l2-expbuf]), but the frame must cross the helper boundary and be
  encoded in software on most hosts, so plain bytes are the right transport.
- Android. Camera2 frames arrive as I420, are converted to RGBA and back to I420
  (`mosh-core/src/native_call/capture/android.rs:150`, `library.rs:265-293`,
  `capture.rs:72-74`). Pushing I420 directly removes both conversions.
- iOS has no engine yet (MOSH-77); the same YUV push applies later.

## Presentation findings

### What flutter_webrtc does

It is not zero-copy. On macOS its renderer converts every frame to I420 and copies it
into its own IOSurface-backed BGRA or NV12 `CVPixelBuffer`, then returns that from
`copyPixelBuffer` ([FlutterRTCVideoRenderer.m:131-210,272-273][fw-darwin]). On Windows
and Linux it converts to RGBA inside `CopyPixelBuffer` on the raster thread
([flutter_video_renderer.cc:21-45][fw-cpp]). What it avoids is everything Mosh does
between steps 2 and 11: one conversion, no IPC, no Dart. That is the target.

### Flutter texture APIs

On macOS `FlutterTexture.copyPixelBuffer` ([FlutterTexture.h:30][fl-texture-h]) accepts
420v, 420f and BGRA through `CVMetalTextureCache` ([FlutterExternalTexture.mm:36-77][fl-ext-mm]).
Windows takes RGBA/BGRA pixel buffers, an `ID3D11Texture2D` or a DXGI shared handle
([flutter_texture_registrar.h:31-79][fl-reg-h]), the latter opened through ANGLE's
`EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE` ([external_texture_d3d.cc:98-105][fl-d3d]). Linux
uploads `FlPixelBufferTexture` RGBA with `glTexImage2D` ([fl_pixel_buffer_texture.cc:104][fl-pixbuf])
or takes a plugin-populated GL texture through `FlTextureGL` ([fl_texture_gl.h:83-97][fl-texgl]).

### Can a separate process show a shared GPU surface?

- macOS. Global IOSurface IDs are deprecated since 10.11 ("Global surfaces are
  insecure", [kIOSurfaceIsGlobal][ios-global]). The supported handoff is a Mach port or
  XPC object ([IOSurfaceCreateMachPort][ios-port], [IOSurfaceCreateXPCObject][ios-xpc]),
  which needs a Mach or XPC channel between the processes. Mosh has none: the child is
  started by `Process.start` and talks over stdio and loopback TCP, which cannot carry
  port rights. Apple documents Mach IPC, XPC and shared memory between sandboxed
  processes through app groups with group-prefixed names ([app groups][app-groups]),
  which would add an entitlement; whether a sandbox-inheriting child can look up a
  service its parent registers is not stated in a primary source. Not verified.
- Windows. Yes: a legacy shared handle can be marshalled to another process
  ([GetSharedHandle][dxgi-handle]) and Flutter's ANGLE path consumes that type. But
  decoded frames are CPU buffers, so the parent must upload them first; the copy moves.
- Linux. `FlTextureGL` could import dmabuf through EGL, but software-decoded frames are
  CPU memory; there is no GPU buffer to export.

Shared memory reaches the same CPU cost with far less platform code. Rust converts
the frame once, at display size, into one of two slots in a region named by a random
capability passed over stdio (like the existing 256-bit frame-channel token), and
sends a 32-byte notice over the existing loopback socket. The child's native texture
returns a pointer into the slot (Windows, Linux) or copies it into an IOSurface-backed
`CVPixelBuffer` from a pool (macOS, about 0.15 ms at 720p). On macOS the region can be
a file in the app container, which the inheriting child shares; on Windows a named file
mapping; on Linux `shm_open` or a file under `$XDG_RUNTIME_DIR`. No new entitlement is
required by this design, which still needs a Mac check.

### Moving presentation into the engine process

This removes the IPC and lets the call window read call state directly; the blocker is
window hosting. Flutter 3.44.7's multi-window API throws unless the `windowing` feature
flag is set and says "Do not use this API in production applications" ([_window.dart][fl-window],
[_features.dart:23][fl-features]). Upgrading does not change that: on 2026-11-10 the
latest stable (3.47.9), `beta` and `master` carry the same warning in `_window.dart`.
The alternative, a second `FlutterEngine` in the main process, is what
`desktop_multi_window` (0.3.1) does, and IVO-23 already tried and removed it: a second
GTK engine crashed with GLX `BadAccess`, and a hung child engine cannot be force-closed
on Windows or macOS (`docs/Proposals/ivo-23-call-window.plan.md:37-44`). It also reverses
ADR 0044's isolation argument (`docs/ADR/0044-native-call-media-over-moss.md:34-37`).
Not now; revisit with ticket 7.

### How other Flutter call apps present video (checked 2026-11-10)

Sources were read at pinned commits; paths are relative to each repository.

- FluffyChat, Commet, LiveKit, Stream and flutter_webrtc show calls inside the main
  window through a texture. None has a separate call window. On Windows and Linux,
  flutter_webrtc converts I420 to RGBA lazily in `CopyPixelBuffer` on the raster thread
  (flutter-webrtc@5ee7ac5e `common/cpp/src/flutter_video_renderer.cc:21-45`); macOS
  fills an IOSurface `CVPixelBuffer` and skips a frame the engine has not consumed
  (`common/darwin/Classes/FlutterRTCVideoRenderer.m:193-207`). LiveKit and Stream
  report the rendered size to the SFU so it sends a smaller layer.
- RustDesk (Flutter 3.24.5) opens extra windows in-process through its own
  desktop_multi_window fork, and Rust calls the texture plugin's C symbol
  `FlutterRgbaRendererPluginOnRgba` directly, so Dart never touches pixels
  (rustdesk@95cca3f6 `src/flutter.rs:283-327`). It hit the same GLX error
  (rustdesk#13511). The GLX crash is flutter/flutter#186577; its fixes (#193530,
  #193126) are unmerged. desktop_multi_window 0.3.1 still has no native close.
- Mixin desktop has no calls; Agora has no Linux SDK; Jitsi's SDK is mobile only.
- Since Flutter 3.44 every desktop engine runs its Dart UI isolate on the platform
  thread, so a busy isolate also delays window events in its process.

None shows a better pattern than this proposal's. Steps 2 to 4 adopt their proven
details: pixels never pass through Dart, a slot the texture has not consumed is
overwritten rather than queued, and the shown size limits what Rust converts.

## Control responsiveness at full screen

The field hypothesis is partly right. Video load does sit on the two Dart isolates
that run the controls: the main isolate spends about 6.8 ms per 720p frame on
`fromList`, `encode` and the socket, and the child about 9.2 ms reassembling the frame
before it decodes it (measured below). Every state change reaches the child through a
serialized `call-present` whose handler also awaits `windowManager.setTitle`
(`call_window_app.dart:91-98`), and the state map includes a diagnostics string with the
live frame rate (`call_media_view.dart:40-43`), so updates are frequent.

Two parts of the hypothesis do not hold. Frames at full screen are at most 1280x720
(3.7 MB), not 8 MB, for the reasons above. And video work in the owner step is about
1 ms per 720p frame (push, preview fit, frame copy), which cannot explain a 4.3 s step.
The code shows a better candidate: every microphone or camera toggle calls
`connection.choices` (`worker.rs:103-110`), which sends `select`
(`connection.rs:104-113`), and `select` stops and restarts both the recording and the
playout device even when neither changed (`mosh-media/webrtc/src/audio.rs:21-37,52-67`).
That runs on the owner thread while it holds the call-state lock (`worker.rs:38-50`),
which Dart's frame and snapshot reads also take. The stall diagnostics have no phase
for it (`diagnostics.rs:69-85`), so a long `step` with short named phases points here.

The button then depends on the round trip finishing. Dart waits up to 5 s for the owner
to apply (`mod.rs:148-175`); on timeout `_change` skips the snapshot read and
`_reconcile` restores the old snapshot (`native_call_session.dart:110-140,214-222`), so
the button shows the old state while Rust applies the new one: the reported symptom.
While `busy`, the child also disables the buttons and drops commands
(`call_controls.dart:49,66`, `call_window_app.dart:122-135`).

How the controls stay responsive regardless of video load:

1. Microphone and camera on/off never touch devices; `select` runs only when an input
   or output ID changes.
2. Choices are recorded and acknowledged without waiting for the owner step; the
   snapshot confirms them. A timeout never restores an older state.
3. The child flips a pressed button to a pending state at once and reconciles on the
   next `call-present`; `setTitle` runs only when the peer changes.
4. Steps 2 to 4 take pixels off both Dart isolates, so frame load can no longer queue
   ahead of taps, commands or presents. Controls keep their own stdio channel.
5. Add a `choices` stall phase so the next field log names the culprit.

## Measurements

Method: Rust 1.96 release and gcc 14 `-O2` builds, each case pinned with `taskset`,
median of 60 runs after 5 warm-ups. libyuv is Debian's 0.0.1904; the engine's exported
`mosh_media_i420_to_rgba` and `mosh_media_scale_rgba`, called from
`.dart_tool/native-media/debug/libmosh_native_media.so` (release libwebrtc m150 libyuv),
agree with it within 1%. nokhwa cases call the pinned nokhwa-core 0.1.9 decoders and a
copy of `packed_bgra::rgb`. The synthetic 720p 4:2:2 q85 JPEG is 41 KiB, smaller than
real webcam frames, so MJPEG figures are lower bounds. Throwaway code lived in
`/tmp/mosh87`. "Core" means one host core at 30 fps.

Helper conversions (ms per frame; ranges are three runs):

| Case | 640x360 | 1280x720 | 1920x1080 |
|------|---------|----------|-----------|
| macOS chain: BGRA to RGB, buffer copy, RGB to RGBA | 1.7 to 2.4 | 6.3 to 8.1 (19 to 24%) | 13.1 to 14.0 |
| same chain without allocator page faults (glibc tuned) | 0.6 | 2.9 | 5.5 |
| YUYV to RGBA (nokhwa) | 1.4 to 3.0 | 5.6 to 6.4 (17 to 19%) | 13.4 to 18.8 |
| NV12 to RGBA (nokhwa) | 1.7 | 4.0 | 9.3 |
| MJPEG to RGBA (nokhwa, mozjpeg) | 1.9 to 2.6 | 11.1 to 11.9 (33 to 36%) | 22.8 to 23.2 |
| MJPEG to planar YCbCr (mozjpeg raw) | 1.5 | 6.1 (18%) | 13.0 |
| MJPEG to I420 (libyuv `MJPGToI420`) |  | 7.0 (21%) |  |

Rows one and two differ by first-touch page faults from three fresh frame-sized
allocations per frame (a fresh 3.7 MB mapping costs 1.06 ms); core and Dart allocate too.

libyuv conversions (ms per frame):

| Case | 640x360 | 1280x720 | 1920x1080 |
|------|---------|----------|-----------|
| ABGR to I420 (encoder push) | 0.05 | 0.20 | 0.37 |
| I420 to ABGR (decoded frame) | 0.07 | 0.29 | 0.64 |
| NV12 to I420 | 0.02 | 0.06 | 0.13 |
| YUY2 to I420 | 0.03 | 0.08 | 0.18 |
| engine `scale_rgba` to half size | 0.11 | 0.35 | 0.82 |
| memcpy of the RGBA frame | 0.04 | 0.15 | 0.29 |

Transport (CPU of both ends per frame, 300 frames, separate processes):

| Case | 640x360 | 1280x720 | 1920x1080 |
|------|---------|----------|-----------|
| pipe, helper stdout to core | 0.73 | 3.64 (11%) | 8.03 (24%) |
| loopback TCP | 0.66 | 2.57 | 5.10 |
| flutter_rust_bridge SSE encode of `Vec<u8>` | 2.9 | 9.5 (28%) | 19.5 (58%) |
| Dart AOT, repository classes: `fromList`, `encode`, channel, `CallWindowInput` | 6.3 | 16.0 (48%) | 30.7 (92%) |

The Dart case imports the three repository files above unchanged and acknowledges each
frame like production (parent 6.8 ms, child 9.2 ms at 720p); it excludes `ImmutableBuffer`
and image decode, which need `dart:ui`.

Per 720p frame on this host the capture path costs 10.5 to 12.5 ms on the macOS code
path (without AVFoundation's conversion) and 15 to 16.5 ms with MJPEG; remote presentation
costs at least 26.3 ms. At 30 fps that is about 1.1 host cores before codecs, audio,
rendering and the local lane. These are host figures for the code path, consistent with
the field report (2 to 2.7 Mac cores, 74% in the call window) but not a proof of its split.

### macOS runner (MOSH-99)

Measured on 2026-11-10 by the `Call video benchmark` workflow (run 42899137250) on
GitHub's `macos-latest` runner, an Apple M1 virtual machine, and on `ubuntu-latest`
(AMD EPYC 9V74). `node scripts/call-video-bench.mjs` drives the repository's own code:
release engine, release mosh-core, compiled Dart. Median ms per frame of 60 runs after
5 warm-ups; in brackets the share of one core at 30 fps. A virtual M1 is not a
user's Mac, so read these as the code path's cost on Apple Silicon, not as field figures.

| Case | macOS 640x360 | macOS 1280x720 | macOS 1920x1080 | Linux 1280x720 |
|------|---------------|----------------|-----------------|----------------|
| RGBA to I420 and encoder push (`Engine::push`) | 0.05 | 0.19 (1%) | 0.53 (2%) | 0.18 (1%) |
| I420 to RGBA (libyuv, as for a decoded frame) | 0.09 | 0.37 (1%) | 0.72 (2%) | 0.21 (1%) |
| preview to half size (`scale_rgba`) | 0.06 | 0.32 (1%) | 0.80 (2%) | 0.22 (1%) |
| frame copy for the bridge (`Frame::clone`) | 0.02 | 0.10 | 0.42 (1%) | 0.09 |
| flutter_rust_bridge encode of the frame | 1.34 (4%) | 4.52 (14%) | 11.4 (34%) | 4.20 (13%) |
| call window socket: encode, send, parse, acknowledge | 3.46 (10%) | 14.1 (42%) | 21.7 (65%) | 5.79 (17%) |
| `ImageDescriptor.raw` decode (flutter_tester, JIT, software) | 0.20 (1%) | 0.31 (1%) | 0.55 (2%) | 0.31 (1%) |

The split holds on Apple Silicon: libyuv work is under 1 ms per 720p frame, while the
bridge encode and the call window socket together cost 18.6 ms, 56% of a core at 30 fps
for the remote lane alone. The socket is 2.4 times dearer on the macOS runner than on
the Linux one. The decode row excludes the GPU upload, which still needs a real Mac.

## Open questions requiring a Mac or Windows device

1. Split of the Mac mini's 2 to 2.7 cores. Run a 720p call with both cameras on,
   windowed and full screen, and record 60 s of
   `top -l 0 -s 5 -stats pid,command,cpu` for the main process, `mosh-call-window`,
   `mosh-camera-capture` and any system camera process that rises with the camera on.
   Repeat with `sample <pid> 10` on the busiest one.
2. Presentation timing. Launch from Terminal with `MOSH_CALL_FRAME_PROFILE=1`
   (inherited by the child, `process_call_window.dart:65-67`) and collect the
   `perf.profile.frame` lines: `roundTripMs`, child `decodeMs`, `copyUs`, `bodyUs`.
3. Cost of AVFoundation's BGRA conversion and of the system MJPEG decode: compare helper
   CPU with BGRA and with 420v output on the same camera (step 5 prototype).
4. Duration of `select` on CoreAudio: time `connection.choices` per toggle and check the
   field log's step stall against its named phases.
5. Whether the inheriting `mosh-call-window` can map a file the parent created in the
   container, and whether `CVPixelBufferPool` copies from it stay near 0.15 ms at 720p.
6. Windows: the camera's chosen native format (helper stderr `configuring ...`), the
   MJPEG decode cost on a typical laptop camera, and named file mapping between parent
   and child under the user's session.
7. Negotiated codec and encoder on Mac-to-Mac calls (the call diagnostics string), since
   only VideoToolbox H.264 yields `CVPixelBuffer` decoder output.
8. Why the Mac mini camera wrote 1920x1080 frames after selecting 1280x720: rerun the
   helper on that camera and compare `configuring` with the first frame's size.

## Proposed follow-up tickets

Filed as MOSH-92 to MOSH-98 in this order; MOSH-99 (macOS CI benchmark) and MOSH-100
(Mac device run before the store release) cover the open questions.

**1. fix(call): call controls respond while video is running**
Scope: microphone and camera on/off stop calling `select`; `select` runs only when an
input or output ID changes. `Hub::choices` stops blocking Dart on the owner step, and a
timeout never restores an older snapshot. The call window shows a pending state on
press; `setTitle` runs only when the peer changes. Add a `choices` stall phase.
Regression tests first: an engine test that toggling the microphone does not restart
devices, and a session test that a slow apply does not revert the button.
Acceptance: on the Mac mini at full screen in a 720p call, 20 consecutive mute and
camera presses each change the button within 100 ms and match the real state within
500 ms; no owner-step stall above 200 ms is attributed to `choices`.

**2. perf(call): call-window video through a native texture, Linux tracer**
Scope: Rust converts the latest local and remote frames once, at display size, into a
two-slot shared-memory region named by a random capability sent over stdio, and sends
a short notice on the existing loopback socket. A Linux `FlPixelBufferTexture` in the
call window reads the slot; the stage uses `Texture`. Delete `nativeCallFrame`, the
Dart frame encode/decode and `CallVideoRenderer`'s RGBA decode once all desktops use it.
Acceptance: the existing real-renderer integration test passes with texture frames;
per-frame CPU of both processes at 720p is below 1 ms on the Linux host; no pixel bytes
cross flutter_rust_bridge or either Dart isolate; renderer crash and restore behave as
documented in `docs/Features/voice-calls.md`.

**3. perf(call): macOS call-window texture from shared frames**
Scope: the ticket 2 producer on macOS with a container file as the region, and a
`FlutterTexture` in `mosh-call-window` that copies the slot into a pooled IOSurface-backed
`CVPixelBuffer` (BGRA, or NV12 when the engine supplies it). No new entitlements.
Acceptance: on the Mac mini at full screen, `mosh-call-window` CPU drops by at least
half against 0.28.2 under the open-question 1 procedure, and the before/after numbers
are recorded in this document.

**4. perf(call): Windows call-window texture from shared frames**
Scope: the ticket 2 producer over a named file mapping; a `PixelBufferTexture` in the
call window reads the slot. Acceptance: the Windows debug integration test passes;
call-window CPU at 720p is measured before and after and recorded here.

**5. perf(camera): native YUV from the camera helper to the encoder**
Scope: the macOS binding requests 420v; Windows and Linux forward NV12/YUYV and decode
MJPEG to planar YUV in the helper. A versioned frame header carries the format. The
engine gains an I420/NV12 push (an ABI addition; confirm before changing the contract)
and fits the preview from YUV. RGBA disappears from capture.
Acceptance: helper and main-process CPU on the Mac mini at 720p30 measured before and
after; 1.38 MB per 720p frame on the pipe; encoder input never passes through RGBA;
camera start, device switching and the 1 s freshness rule still pass their tests.

**6. perf(call): Android camera frames reach the encoder as I420**
Scope: `cameraFrame` uses the ticket 5 push instead of `i420_to_rgba`; the preview is
converted once. Acceptance: no RGBA round trip on Android capture; arm64 call tests pass.

**7. research: call window as a second view of the main engine**
Scope: track Flutter's desktop multi-window API (issue 30701). When it is usable
without a feature flag on stable, spike the call window as a second view showing the
ticket 2 to 4 textures directly, and update ADR 0044. Acceptance: a written go/no-go
with a working spike on macOS; if go, a plan to delete the child process, stdio pipe,
frame channel and `mosh-call-window` copy.

[avf-output]: https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput
[avf-settings]: https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput/videosettings
[tn3121]: https://developer.apple.com/documentation/technotes/tn3121-selecting-a-pixel-format-for-an-avcapturevideodataoutput
[ios-global]: https://developer.apple.com/documentation/iosurface/kiosurfaceisglobal
[ios-port]: https://developer.apple.com/documentation/iosurface/iosurfacecreatemachport(_:)
[ios-xpc]: https://developer.apple.com/documentation/iosurface/iosurfacecreatexpcobject(_:)
[app-groups]: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups
[dxgi-handle]: https://learn.microsoft.com/en-us/windows/win32/api/dxgi/nf-dxgi-idxgiresource-getsharedhandle
[mf-reader]: https://learn.microsoft.com/en-us/windows/win32/medfound/processing-media-data-with-the-source-reader
[v4l2-expbuf]: https://www.kernel.org/doc/html/latest/userspace-api/media/v4l/vidioc-expbuf.html
[fw-darwin]: https://github.com/flutter-webrtc/flutter-webrtc/blob/5ee7ac5eb5ad049b1ef847244c566ce2d7fe235e/common/darwin/Classes/FlutterRTCVideoRenderer.m#L131-L210
[fw-cpp]: https://github.com/flutter-webrtc/flutter-webrtc/blob/5ee7ac5eb5ad049b1ef847244c566ce2d7fe235e/common/cpp/src/flutter_video_renderer.cc#L21-L45
[fl-texture-h]: https://github.com/flutter/flutter/blob/84fc5cbb223bc12f83d65b647ff8a56caf779ffd/engine/src/flutter/shell/platform/darwin/common/framework/Headers/FlutterTexture.h#L30
[fl-ext-mm]: https://github.com/flutter/flutter/blob/84fc5cbb223bc12f83d65b647ff8a56caf779ffd/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterExternalTexture.mm#L36-L77
[fl-reg-h]: https://github.com/flutter/flutter/blob/84fc5cbb223bc12f83d65b647ff8a56caf779ffd/engine/src/flutter/shell/platform/common/public/flutter_texture_registrar.h#L31-L79
[fl-d3d]: https://github.com/flutter/flutter/blob/84fc5cbb223bc12f83d65b647ff8a56caf779ffd/engine/src/flutter/shell/platform/windows/external_texture_d3d.cc#L98-L105
[fl-pixbuf]: https://github.com/flutter/flutter/blob/84fc5cbb223bc12f83d65b647ff8a56caf779ffd/engine/src/flutter/shell/platform/linux/fl_pixel_buffer_texture.cc#L104
[fl-texgl]: https://github.com/flutter/flutter/blob/84fc5cbb223bc12f83d65b647ff8a56caf779ffd/engine/src/flutter/shell/platform/linux/public/flutter_linux/fl_texture_gl.h#L83-L97
[fl-window]: https://github.com/flutter/flutter/blob/84fc5cbb223bc12f83d65b647ff8a56caf779ffd/packages/flutter/lib/src/widgets/_window.dart
[fl-features]: https://github.com/flutter/flutter/blob/84fc5cbb223bc12f83d65b647ff8a56caf779ffd/packages/flutter/lib/src/foundation/_features.dart#L23
