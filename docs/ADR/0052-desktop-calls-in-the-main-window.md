# ADR 0052: desktop calls in the main window, video through a Rust-fed texture

Date: 2026-11-10
Status: Accepted. Linux, macOS and Windows are implemented (MOSH-93, MOSH-94,
MOSH-95). No platform starts the call window process any more; its removal is
pending (MOSH-101).

## Context

Desktop calls show video in a separate call window: a second process running its
own Flutter engine (IVO-23, [ADR 0044](0044-native-call-media-over-moss.md)).
Frames go from Rust through flutter_rust_bridge into Dart, over a loopback socket
to the child, and are decoded there. On the Linux host a remote 720p frame costs
at least 26 ms of CPU on that path, and both Dart UI isolates carry the work. Since
Flutter 3.44 those isolates run on the platform thread. Every call control
round-trips child → stdio → parent → Rust → parent → child, and on the Mac mini the
buttons stopped reflecting their state at full screen (#140, MOSH-92).

The measurements, the options per platform and how other Flutter call apps do it
are in [MOSH-87's research](../Proposals/mosh-87-video-pipeline.research.md).
Mosh has not been released, so the call presentation can change freely.

## Decision

On desktop, a call is presented in the main window, as on Android and iOS. Its
video is a Flutter `Texture` backed by a native pixel-buffer texture per platform
(`FlutterTexture` on macOS, `PixelBufferTexture` on Windows, `FlPixelBufferTexture`
on Linux). Rust feeds it directly, as RustDesk does:

- the platform plugin hands Dart the texture's native handle once;
- Dart passes that handle to Rust;
- Rust writes each frame into the texture's buffer at the size it is shown and
  marks it available.

A frame the engine has not consumed yet is overwritten, never queued. Pixels never
pass through flutter_rust_bridge or Dart.

The call can take the whole main window and switch it to full screen. While the
user browses chats it shrinks to a mini view.

The separate call-window process, its stdio pipe, the frame channel and the macOS
`mosh-call-window` copy are deleted once every desktop uses the texture.

A pop-out call window returns only through Flutter's own multi-window API, once it
is stable and not behind a feature flag (MOSH-98).

## Alternatives considered

- **Keep the child process and share frames through shared memory into a texture
  there.** This was the research's recommendation. It saves the same CPU but keeps:
  - the process;
  - the control round trip;
  - the sandbox copy on macOS;
  - a shared-memory transport on three platforms.
- **A second Flutter engine in the main process** (`desktop_multi_window`). Rejected
  in IVO-23, and still broken:
  - GLX `BadAccess` on Linux (flutter/flutter#186577, fixes unmerged);
  - no native close of a hung window.
- **A native, non-Flutter call window** (as Telegram Desktop or Zoom have). It means
  building the call UI three times.
- **Flutter's multi-window API.** Still marked not for production on stable 3.47.9,
  beta and master.

No Flutter app we found has a separate call window. FluffyChat, Commet, LiveKit,
Stream and flutter_webrtc all render calls through a texture in the host window.

## Consequences

- Controls and call state live in one process. No call-control IPC remains.
- One presentation path for desktop and mobile. Mobile moves to the same texture
  later (MOSH-102).
- The isolation argument of ADR 0044 changes. A presentation failure is no longer
  contained in a child process. What remains in the main process is a small native
  texture, not a second engine, and the media owner stays in Rust as before.
- Users cannot place the call in its own OS window until MOSH-98.
- [ADR 0044](0044-native-call-media-over-moss.md)'s child-window statements, the
  architecture overview and `docs/Features/voice-calls.md` hold until
  MOSH-101 removes the process, and change with it.
