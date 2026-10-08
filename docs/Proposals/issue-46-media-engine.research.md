# Issue 46: media engine and desktop ownership

Research date: 2026-10-08. Source research only, with no dependencies, builds,
probes or code changes. Agreed boundaries are a parent audio/video engine,
a renderer-only child, and all networking through extensible Moss. No new
mandatory server or old-call-client compatibility is required.

## Recommendation and confidence

RingRTC's low-level Rust WebRTC binding is the strongest candidate for Moss.
It provides virtual UDP injection, audio devices, WebRTC audio processing,
video encoding/decoding and packet feedback. Use a MOSH-owned adapter without
Signal's service or CallManager. The binary integration remains untested.

Transport/media APIs are confirmed; MOSH builds and connections are untested.
Resolve callback declarations, desktop linking and key setup before adoption.

## Exact sources and documentation

- RingRTC `331d601894f931337d24e9d56c68b94d28fc4555`, version 2.72.1.
- Its WebRTC tag `7871n` resolves to
  `25e48ee75ff1b6fcab10c6a200f233d449dd421e`.
- Native upstream WebRTC `e40a408898b7ea16e59ebc8ea96c6d42c8f8753d`.
- flutter_webrtc `381926ca5b1bfea4e8b46743eee97c2ee9a9a72b` and its desktop
  wrapper `8ee1ef5e107d7d465d4a2266a3c9cb58e8a9dac5`.
- Context7 resolved both libraries. RingRTC's low-level query found no docs;
  its build snippets are older than this pinned source. [Versions][versions]

## Public Rust APIs work below CallManager

`ringrtc::webrtc` is public. `PeerConnectionFactory::new` accepts audio
configuration and a boolean selecting injected networking.
`create_peer_connection` accepts an observer, connection kind, ICE servers,
and outgoing audio/video tracks. None of these functions takes a CallManager,
Signal account or service client. This establishes a service-independent
integration boundary at source level. [Public modules][modules],
[factory][factory]

| Requirement | Existing interface |
| --- | --- |
| Packet send and receive | `InjectableNetwork::set_sender`, `PacketSender::send_udp`, `receive_udp` |
| Local and remote descriptions | `create_offer`, `create_answer`, `set_local_description`, `set_remote_description` |
| ICE events and input | Observer candidate/connection callbacks and `add_ice_candidate_from_sdp` |
| Outgoing video | `create_outgoing_video_source`, `create_outgoing_video_track`, `VideoSource::push_frame` |
| Incoming video | Observer `handle_incoming_video_frame` with frame-content delivery enabled |
| Audio devices and mute | Factory device enumeration/selection; track and recording/playout enable controls |

These APIs are untested here. [Networking][network], [PeerConnection][pc], [media][media], [observer][observer]

The crate compiles Signal-specific modules and mandatory `zkgroup`/libsignal
and protobuf dependencies even for low-level use. [Cargo dependencies][cargo]

## Signaling and encryption have a concrete limitation

The Rust binding exports SDP serialization but no generic SDP string parser.
Its available `offer_from_v4` and `answer_from_v4` reconstruct descriptions
from RingRTC's negotiation parameters. Native reconstruction disables DTLS
and uses manually supplied SRTP keys. MOSH cannot assume ordinary SDP exchange
plus DTLS works through the current Rust API. [Description API][sdp],
[native reconstruction][native-pc]

A source-level route adapts authenticated MLS call messages to the engine's
negotiation parameters and installs fresh, direction-specific SRTP keys using
`disable_dtls_and_set_srtp_key`. Upstream demonstrates this sequence.
WebRTC owns SRTP/SRTCP, replay protection and media processing. MOSH must
specify call/device binding and key generation/lifetime. No CallManager is needed.
[Upstream key/setup sequence][connection]

The MOSH public call protocol should use its own types and keep RingRTC's
protobuf inside the adapter. That boundary is a design recommendation.
If ordinary SDP/DTLS is preferred instead, a native parser adapter or an
upstream API addition needs investigation. That path is not demonstrated here.

## Injected UDP can keep the entire network path in Moss

The native factory selects an injected `BasicPortAllocator` and application
virtual interfaces. Its UDP socket forwards packets through the callback and
injects received packets into the corresponding virtual socket. TCP and DNS
constructors return null. Direct PeerConnection disables TCP ICE; use no ICE
servers. These paths provide packet confinement without another STUN/TURN
service. Runtime confinement still needs a test.
[Native factory][native-factory], [native injected sockets][native-network]

ICE remains inside the virtual network and performs connectivity checks over
Moss-carried packets. Moss remains responsible for real discovery, NAT traversal
and relay. This is UDP encapsulation through Moss, not TURN compatibility.
The upstream direct example demonstrates packet forwarding through an injected
router. Signal Desktop's factory uses normal networking, so that application
does not prove the injected path's production behavior.
[Direct example][direct], [Electron factory][electron]

The following adapter design is an inference from those APIs:

1. Bind virtual endpoint addresses to the accepted call and its selected device
   pair. Exchange virtual ICE candidates through authenticated call signaling.
2. Send the complete UDP payload and virtual source/destination ports in a
   directed Moss envelope. Do not substitute a gossip room or process-wide
   destination inferred solely from an IP supplied by a remote packet.
3. Validate the actual Moss sender, call generation and endpoint mapping before
   invoking `receive_udp`. Preserve payloads and packet boundaries, including
   connectivity checks and encrypted media feedback.
4. Keep callbacks nonblocking, queues bounded and packet age short. Drop stale
   datagrams on overload; expose loss and queue timing for acceptance checks.
   Moss direct/relay changes should not require replacing virtual endpoints.

The injected socket reports sent-packet timing at callback invocation.
Its Rust sender returns no enqueue status; native `SendUdp` ignores the
callback result and returns the payload size. A long queue below this point
distorts timing and creates media latency. The adapter needs queue discipline,
not another congestion controller or codec. [Native injected sockets][native-network]

## Audio and video processing are already implemented

The desktop factory uses WebRTC audio codecs, mixer and audio processing.
`AudioConfig` defaults enable AEC, noise suppression, gain control and a
high-pass filter. cubeb provides devices, change notifications and selection.
Real-device AEC and permissions require acceptance. [Native factory][native-factory],
[audio configuration][factory], [audio-device implementation][adm]

Outgoing video accepts copied I420, NV12 or RGBA frames and adapts output
dimensions/frame rate. The Rust binding does not provide a camera enumerator
or capture session; MOSH needs an application-side capture adapter.
The desktop native factory instantiates libvpx VP8/VP9 encoders and decoders,
so hardware H.264/AV1 support must not be promised for this candidate.
[Media interface][media], [codec factory][native-factory]

Incoming events include decoded frames when enabled. The native observer copies
and rotates them. MOSH needs bounded transfer and child-local textures.
Platform adapters own capture/permissions/rendering; the engine owns codecs,
AEC, jitter buffering and media feedback.
[Rust observer][observer], [native observer][native-observer]

## Desktop artifacts and build risks

RingRTC's actual Rust package uses `src/rust/build.rs`. Its
`prebuilt_webrtc` feature enables native media and invokes
`bin/fetch-artifact`; `injectable_network` separately exposes the Rust hook.
The newer `webrtc-sys` workspace crate is not a dependency of this RingRTC
package at this revision. Do not confuse its build logic with the package
we would integrate. [Package manifest][cargo], [actual build script][build]

The archive manifest pins SHA-256 values for Windows, macOS and Linux on x64
and arm64. The fetch script constructs versioned URLs under
`build-artifacts.signal.org/libraries` and verifies hashes.
Native injection sources are unconditional in the common RFFI source list
on all three desktop OSes, and the WebRTC target includes RFFI.
This strongly supports their inclusion in matching upstream archives.
Archive availability, actual exported symbols and linking were not tested.
[Artifact hashes][hashes], [fetch script][fetch],
[RFFI targets][rffi-build], [WebRTC target][webrtc-build]

| Area | Evidence and remaining check |
| --- | --- |
| C++ ABI | Rust uses C exports and opaque native pointers. Match the RingRTC headers and WebRTC tag exactly. The sender callback declarations currently disagree on return types; resolve before adoption. |
| Windows | Build script handles MSVC libraries; upstream desktop build sets static CRT. Prebuilts are release artifacts while Cargo debug builds select debug CRT libraries. Prove MOSH debug integration, which the repo requires. |
| macOS | Build script links system frameworks, libc++ and a discovered clang runtime. Verify both architectures and the existing universal packaging/signing workflow. |
| Linux | cubeb requires audio backend prerequisites. Upstream configuration requires libpulse. Verify the current desktop distro baseline and packaging. |
| Toolchain | RingRTC pins Rust 1.97.1; MOSH pins 1.96.0. This difference is not proof that MOSH must upgrade, but compatibility remains untested. |
| Maintenance | Signal maintains its WebRTC fork. Prefer pinned upstream source/artifacts and a MOSH adapter over a private codec/network fork. First-time source builds require the Chromium toolchain and substantial downloads; no build-duration measurement exists. |

[Actual linker configuration][build], [upstream desktop build][desktop-build],
[build guide][building], [RingRTC toolchain][toolchain],
[Linux configuration][cargo-config]

The callback discrepancy is concrete. Rust's sender and delete callbacks return
`()`; the matching C++ header declares both as returning `int`.
Native code ignores their values, but that does not resolve the declaration
mismatch. Treat it as an ABI acceptance blocker, not a demonstrated crash.
An upstream correction or a verified adapter must settle it.
[Rust callback definitions][network], [C++ callback declarations][network-header]

RingRTC is AGPL-3.0-only; `mosh-core` declares GPL-3.0-or-later.
Those facts require an explicit dependency/distribution decision.
This research does not establish a legal incompatibility. [RingRTC manifest][cargo],
[MOSH manifest](../../mosh-core/Cargo.toml)

## Parent media and renderer-only child

The parent owns the engine, camera and audio lifetime, authenticated signaling,
keys and the one Moss node. The child receives presentation frames and call-bound
commands. A child failure must leave the parent call and audio alive.
These agreed boundaries preserve the existing
[independent call-window behavior](../Features/voice-calls.md).

Flutter texture IDs belong to a view's registry. Passing the parent's ID does
not render its texture in another process. Add bounded native frame IPC and
child-local textures; do not route every decoded frame through JSON/base64
stdio. A tightly packed 720p/30 I420 surface alone is about 41.5 MB/s before
extra copies. Shared memory is a candidate, not a selected or tested mechanism.
[Flutter texture contract](https://api.flutter.dev/flutter/widgets/Texture-class.html)

## Comparison and acceptance gates

A native libwebrtc `Call` adapter provides RTP/RTCP callbacks and media streams,
but requires more native lifecycle, codec/device factories, packet accounting
and encryption work. Raw `Transport` does not establish DTLS-SRTP.
It is the fallback if RingRTC's blockers remain unresolved.
[Call API][call], [packet receiver][receiver], [transport API][transport],
[direct-transport example][direct-transport], [DTLS-SRTP][dtls]

flutter_webrtc offers capture/textures, but its inspected public wrapper has no
matching injected network or `Call` hook. Frame encryption does not supply it.
Native work remains necessary. [Wrapper headers][wrapper],
[plugin encryption](https://github.com/flutter-webrtc/flutter-webrtc/blob/381926ca5b1bfea4e8b46743eee97c2ee9a9a72b/Documentation/E2EE.md)

Before adopting RingRTC, resolve ABI declarations and prove pinned standalone
linking on macOS/Windows plus Linux, including Windows debug. Then demonstrate
two independent MOSH installations with audio, video, RTCP/feedback and
authenticated device-bound media through directed/relayed Moss only.
Measure capture/IPC latency, CPU, relay load and recovery, and exercise child
failure/recreation. These are future feasibility checks, not work already run.

Reject a candidate for mandatory external services, an uncontrollable network
path, unresolvable linking/ABI or custom codecs/AEC/congestion control. Source
shows no such architectural requirement for RingRTC. Camera/renderer adapters,
endpoint mapping, key setup and packaging remain necessary integration work.

[versions]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/config/version.properties
[modules]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/src/lib.rs
[factory]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/src/webrtc/peer_connection_factory.rs
[network]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/src/webrtc/injectable_network.rs
[pc]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/src/webrtc/peer_connection.rs
[media]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/src/webrtc/media.rs
[observer]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/src/webrtc/peer_connection_observer.rs
[cargo]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/Cargo.toml
[sdp]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/src/webrtc/sdp_observer.rs
[native-pc]: https://github.com/signalapp/webrtc/blob/25e48ee75ff1b6fcab10c6a200f233d449dd421e/ringrtc/rffi/src/peer_connection.cc
[connection]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/src/core/connection.rs
[native-factory]: https://github.com/signalapp/webrtc/blob/25e48ee75ff1b6fcab10c6a200f233d449dd421e/ringrtc/rffi/src/peer_connection_factory.cc
[native-network]: https://github.com/signalapp/webrtc/blob/25e48ee75ff1b6fcab10c6a200f233d449dd421e/ringrtc/rffi/src/injectable_network.cc
[direct]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/src/bin/direct.rs
[electron]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/src/electron.rs
[adm]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/src/webrtc/audio_device_module.rs
[native-observer]: https://github.com/signalapp/webrtc/blob/25e48ee75ff1b6fcab10c6a200f233d449dd421e/ringrtc/rffi/src/peer_connection_observer.cc
[build]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/build.rs
[hashes]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/config/webrtc_artifact_checksums.json
[fetch]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/bin/fetch-artifact.py
[rffi-build]: https://github.com/signalapp/webrtc/blob/25e48ee75ff1b6fcab10c6a200f233d449dd421e/ringrtc/rffi/BUILD.gn
[webrtc-build]: https://github.com/signalapp/webrtc/blob/25e48ee75ff1b6fcab10c6a200f233d449dd421e/BUILD.gn
[desktop-build]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/bin/build-desktop
[building]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/BUILDING.md
[toolchain]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/rust-toolchain
[cargo-config]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/.cargo/config.toml
[network-header]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/src/webrtc_include/injectable_network.h
[call]: https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/call/call.h
[receiver]: https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/call/packet_receiver.h
[transport]: https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/api/call/transport.h
[direct-transport]: https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/test/direct_transport.cc
[dtls]: https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/pc/dtls_srtp_transport.h
[wrapper]: https://github.com/webrtc-sdk/libwebrtc/tree/8ee1ef5e107d7d465d4a2266a3c9cb58e8a9dac5/include
