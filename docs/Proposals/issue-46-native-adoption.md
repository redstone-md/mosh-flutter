# Native media dependency decision for #46

The selected-device coordination is implemented in `c2a21caf`. The existing
RingRTC candidate now also exports real decoded RGBA through a bounded binary
ABI. A Linux 10-second Moss run copied 290/288 changing remote frames with a
maximum observed export age of 15/14 ms. This establishes the frame-copy boundary;
it does not establish camera capture or desktop presentation.

Approved production dependencies:

- Keep RingRTC 2.72.1 at commit `331d601894f931337d24e9d56c68b94d28fc4555`, with
  the existing pinned WebRTC artifact and existing ABI patch. Build its Rust
  dependency graph as a separate dynamic library: its mandatory libsignal/hax
  graph conflicts with the core's OpenMLS/hax graph. The main process loads
  that library and owns the single audio/video engine. RingRTC and mandatory
  Signal components carry AGPL-3.0; this is a deliberate dependency choice,
  not a claim about licensing obligations.
- Add exact `nokhwa = 0.10.11`, with default features disabled and only
  `input-native` and `decoding`, for camera capture on the three desktop OSes.
  No threaded-output or unsafe `Send` camera feature. It uses AVFoundation,
  Media Foundation and V4L2; camera acquisition and reads stay on one thread.
- Add explicit X25519/HKDF/SHA-256 dependencies to the isolated engine, using
  versions already present in that graph. Use one fresh ephemeral key pair per
  selected media session. MLS authenticates the public exchange, bound to the
  DM/call and both selected leaf identities. Private keys and SRTP keys never
  enter Dart or the call-window process. No copied private Signal helper.

The camera backends expose blocking reads without a portable cancellation
deadline. Put camera acquisition in a capture-only helper process owned by the
main call owner, with bounded binary frame output and parent-death cleanup.
Camera off disables the native video track immediately and terminates that
helper, releasing the device even when a driver read is blocked. The helper
owns no audio, call engine, transport or keys. The existing desktop call window
remains presentation-only. This is a resource boundary for camera drivers,
not a second call owner.

Package the engine and helper through the existing native build hook. Keep
the dependency behind a Mosh-owned adapter; remove the current call audio
pipeline after real duplex/mute/receive-only checks pass. Android/iOS keep the
current path until their separately scoped native integration exists.

Checks before enabling the desktop adapter: selected-device authenticated key
exchange; directed Moss packets only; real duplex audio, independent mute and
receive-only behavior; capture off and helper failure; decoded presentation
through bounded IPC; no engine/audio/key ownership in the renderer. Linux runs
locally. The user performs physical Windows/macOS acceptance; missing hardware
access does not stop best-effort implementation.

Remaining platform risks: macOS universal packaging and permissions, Windows
driver behavior, software encoder CPU, camera backend cancellation, relay
capacity and actual packet completion feedback. Hardware encoding remains a
runtime fact rather than an inferred property of capture or decoding.

Root `AGENTS.md` requires asking before dependency changes. The user approved
the dependencies and managed camera helper on 2026-10-09 after reviewing this
proposal. Implementation continues under that authorization.

The desktop adapter is implemented and enabled after local native duplex,
receive-only, camera-off/driver-failure and real Flutter window checks. See
[current results](issue-46-native-implementation.results.md). Authenticated offers
identify the media path, excluding incompatible mobile installations until their
native integration follows. Desktop bundles include license notices; process
isolation does not exempt the combined distribution from license obligations.
