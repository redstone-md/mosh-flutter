# Issue 46: media engine and desktop ownership

Research date: 2026-10-08. These are source findings and design candidates,
not an implemented or tested media integration. All network media must use
Moss. The existing desktop call window is a separate process.

## Sources inspected

- Native WebRTC revision `e40a408898b7ea16e59ebc8ea96c6d42c8f8753d`.
- flutter_webrtc revision `381926ca5b1bfea4e8b46743eee97c2ee9a9a72b`.
- webrtc-sdk/libwebrtc revision `8ee1ef5e107d7d465d4a2266a3c9cb58e8a9dac5`.
- Signal RingRTC revision `331d601894f931337d24e9d56c68b94d28fc4555`.
- Context7 `/flutter-webrtc/flutter-webrtc` documents plugin capture,
  rendering, packaging and frame encryption. Its results did not establish
  a public custom RTP transport hook. Native API claims below come from source.

## Native libwebrtc can accept an application transport

`webrtc::Transport` exposes `SendRtp` and `SendRtcp`. Both receive packet bytes
and `PacketOptions`. Video send configuration accepts this transport;
video receive configuration accepts a transport for outgoing RTCP and a
decoded-frame renderer. `Call` creates audio/video send and receive streams.
These are real native interfaces, independent of the Dart plugin.
[Transport](https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/api/call/transport.h),
[send stream](https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/call/video_send_stream.h),
[receive stream](https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/call/video_receive_stream.h),
[Call](https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/call/call.h).

`Call::Receiver()` accepts RTP and RTCP through `PacketReceiver`.
RTP reception uses a parsed `RtpPacketReceived`; RTCP uses a byte buffer.
The API specifies worker/network thread restrictions. WebRTC's direct-transport
test demonstrates packet forwarding, network-state reporting and
`Call::OnSentPacket` accounting. A Moss adapter must preserve packet boundaries,
timing, feedback and teardown rules, rather than only copy encoded video frames.
[PacketReceiver](https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/call/packet_receiver.h),
[direct transport](https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/test/direct_transport.cc).

The send source and receive renderer use WebRTC video interfaces. Native camera
capture has a factory and a frame callback. Codec factories include VP8;
H.264 and AV1 depend on build configuration. Source availability does not prove
camera behavior, hardware acceleration, CPU cost or 720p/30 on our packaged hosts.
[capture factory](https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/modules/video_capture/video_capture_factory.h),
[capture callback](https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/modules/video_capture/video_capture.h),
[encoder factory](https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/media/engine/internal_encoder_factory.cc).

These raw transport callbacks do not establish a DTLS-SRTP connection.
The video transport adapter delegates packet bytes directly; WebRTC's
`DtlsSrtpTransport` separately derives SRTP keys from a DTLS transport.
Using `Call` directly therefore requires an explicit authenticated media
encryption contract, including RTP and RTCP protection. Neither RTP nor the
word "WebRTC" proves end-to-end encryption over Moss.
[packet adapter](https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/video/transport_adapter.cc),
[DTLS-SRTP transport](https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/pc/dtls_srtp_transport.h).

## flutter_webrtc is useful prior art, not a demonstrated Moss adapter

The plugin supports desktop audio/video and provides camera capture and Flutter
rendering. Its documented frame encryption attaches to PeerConnection senders
and receivers; that hook does not replace ICE, DTLS or packet transport.
[platform support](https://github.com/flutter-webrtc/flutter-webrtc/blob/381926ca5b1bfea4e8b46743eee97c2ee9a9a72b/README.md),
[frame encryption](https://github.com/flutter-webrtc/flutter-webrtc/blob/381926ca5b1bfea4e8b46743eee97c2ee9a9a72b/Documentation/E2EE.md).

The inspected Windows/Linux native wrapper exposes PeerConnection, tracks and
RTP parameters. Its public headers do not expose `webrtc::Call`, packet
`Transport`, or `PacketReceiver`. A sender named `RTCRtpSender` is a track and
parameter interface, not a raw RTP send callback. We have not verified that
distributed binaries export the lower-level symbols needed by a separate adapter.
[public headers](https://github.com/webrtc-sdk/libwebrtc/tree/8ee1ef5e107d7d465d4a2266a3c9cb58e8a9dac5/include),
[sender interface](https://github.com/webrtc-sdk/libwebrtc/blob/8ee1ef5e107d7d465d4a2266a3c9cb58e8a9dac5/include/rtc_rtp_sender.h),
[wrapper build](https://github.com/webrtc-sdk/libwebrtc/blob/8ee1ef5e107d7d465d4a2266a3c9cb58e8a9dac5/BUILD.gn).

Desktop packaging also differs. Windows/Linux download versioned native wrapper
archives. macOS depends on `WebRTC-SDK` through CocoaPods. A raw `Call` adapter
must establish a reproducible native library build and compatible headers for
each platform; reusing the plugin's download URL does not establish that support.
The upstream wrapper build uses a WebRTC checkout, GN and Ninja.
[desktop binary manifest](https://github.com/flutter-webrtc/flutter-webrtc/blob/381926ca5b1bfea4e8b46743eee97c2ee9a9a72b/third_party/libwebrtc_version.ini),
[macOS podspec](https://github.com/flutter-webrtc/flutter-webrtc/blob/381926ca5b1bfea4e8b46743eee97c2ee9a9a72b/macos/flutter_webrtc.podspec),
[native build instructions](https://github.com/webrtc-sdk/libwebrtc/blob/8ee1ef5e107d7d465d4a2266a3c9cb58e8a9dac5/README.md).

## RingRTC provides another real transport hook

Signal's maintained RingRTC contains a Rust `InjectableNetwork` with
`set_sender`, a `PacketSender::send_udp` callback, virtual network interfaces and
`receive_udp`. The factory exposes it behind the `injectable_network` feature.
This is prior art for an application-carried network under PeerConnection,
rather than direct `Call` RTP transport. It must not be described as ordinary
flutter_webrtc functionality or standard TURN compatibility.
[Rust injectable network](https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/src/webrtc/injectable_network.rs),
[factory](https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/src/webrtc/peer_connection_factory.rs).

RingRTC's build guide covers desktop Electron builds and prebuilt WebRTC use.
It is AGPL-3.0-only. This research does not prove that its current distributions
enable injectable networking on our three desktop targets or supply Flutter
camera/texture integration. A candidate must verify virtual address-to-Moss-peer
mapping, complete packet confinement, packaging and media ownership.
[build guide](https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/BUILDING.md),
[project and license](https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/README.md).

## Desktop process ownership remains a product decision

Flutter texture IDs belong to a view's texture registry. Passing a parent's
texture ID to the call child cannot display the parent's texture. The plugin
renderer binds its local texture to a local native stream. Video needs actual
frame or packet transfer, or a media engine in the child.
[Flutter Texture contract](https://api.flutter.dev/flutter/widgets/Texture-class.html),
[plugin renderer](https://github.com/flutter-webrtc/flutter-webrtc/blob/381926ca5b1bfea4e8b46743eee97c2ee9a9a72b/lib/src/native/rtc_video_renderer_impl.dart).

The following tradeoffs are design inferences, not measured performance.
Existing ownership comes from [voice calls](../Features/voice-calls.md) and
[the independent-window plan](ivo-23-call-window.plan.md).

| Ownership | Benefit | Work and consequence |
| --- | --- | --- |
| Parent owns media; child presents video | Preserves working audio and parent call ownership when the child fails | Add bounded native frame transfer and child texture registration. Cross-process GPU sharing differs by OS; decoded CPU frames cost copies and bandwidth. Compressed transfer adds child decoding, including local preview if sent compressed. |
| Parent owns Moss/signaling; child owns media | Camera, codecs and displayed textures stay together | Add bounded binary packet IPC and authenticated setup. Child failure loses media unless the parent has a separate recovery path. Current controls-only child and audio ownership must change. |

The current stdio protocol carries display metadata and commands. It supplies no
video path. Local IPC must bind every operation to the current call and selected
device, reject stale work, bound queues and preserve close/minimize/recreate
behavior. A second process must not initialize another installation Moss node.
At 1280x720 and 30 fps, tightly packed I420 alone is about 41.5 MB/s per video
surface before extra copies. This arithmetic explains why decoded-frame IPC
needs a deliberate design; it does not select the final IPC mechanism.

## Required evidence before choosing the engine

1. Link a pinned native candidate on macOS and Windows, with Linux checks.
   Prove the required transport hooks exist in the shipped artifacts.
2. Demonstrate bidirectional audio and video through directed Moss packets,
   including RTCP/feedback, relay and recovery. Prove no separate network path.
3. Verify authenticated media protection and selected-device binding.
4. Exercise capture, decode and textures in the chosen process layout, including
   child failure and recreation. Measure queue delay, CPU and relay bandwidth.

These are proposed future feasibility checks. No library was installed, no
runtime probe ran, and no production code or Moss source changed for this note.
