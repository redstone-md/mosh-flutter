# Issue 46: native media candidates for a Moss carrier

Research date: 2026-10-08. Source review only. No dependencies, builds or runtime probes.
The agreed boundary is one native audio/video engine in the main process, child-window video presentation, and all network packets through Moss. macOS and Windows require acceptance; Linux remains supported. Android follows later.
Context7 documentation was consulted for LiveKit Rust, GStreamer and flutter_webrtc; transport conclusions below use the linked primary source or official API documentation.

## Recommendation and its limits

No inspected package is a turnkey solution for this boundary. My first feasibility candidate is RingRTC's lower-level WebRTC factory with its existing injectable network, without Signal's CallManager. This is a design judgement: reusing its duplex audio, AEC, codecs and congestion machinery should require less custom media logic than composing those functions ourselves. Its Signal-specific description/key API, dependency graph and transport callback problems must pass the gates below before adoption.

GStreamer is the strongest alternative when a stable, application-owned packet bridge matters more than reuse of a complete calling engine. It has normal desktop distributions and explicit RTP/RTCP pads. Mosh would own the pipeline, duplex echo-reference routing and congestion-budget wiring. A bare native libwebrtc `Call` shim is a credible fallback if RingRTC's integration costs are unacceptable, but Mosh would maintain more C++ configuration and build machinery. These are comparative assessments, not measured integration costs.

## Comparative matrix

| Candidate | Verified media and desktop evidence | Actual Moss transport boundary | Integration judgement |
| --- | --- | --- | --- |
| RingRTC lower factory | Native WebRTC AV, default AEC/NS/AGC, cubeb audio devices; application-fed video frames. Desktop build includes injectable-network sources. [Factory][ring-factory], [audio module][ring-audio], [media][ring-media], [native factory][ring-native], [desktop build][ring-build] | Public Rust `InjectableNetwork` supplies virtual interfaces, outgoing UDP callback and incoming UDP injection under PeerConnection. Native allocator uses the injected network; TCP and DNS constructors return null. [Rust network][ring-network], [native network][ring-native-network] | Best first validation candidate. Requires virtual endpoint mapping, application camera/presentation, Signal V4/media-key adaptation, packaging verification and bounded carrier feedback. |
| LiveKit Rust lower `libwebrtc` crate | Real native codec factories, audio-processing builder, platform microphone/speaker controls and raw video sources; desktop CI matrix. [Native factory][lk-native], [device controls][lk-devices], [build matrix][lk-builds] | Public `RtcConfiguration` configures ICE and `create_peer_connection` accepts that configuration. Inspected native factory uses its runtime socket server. No public injected packet transport was established. [Rust factory][lk-factory], [native factory][lk-native] | Viable full media engine, but Moss needs a maintained native socket/allocator extension. The higher `livekit` Room SDK adds server/token assumptions and is outside this shortlist. |
| Native libwebrtc with a Mosh C ABI shim | `Call` creates audio/video streams; device/capture and codec modules exist. Official native build supports macOS, Windows, Linux and Android. [Call][native-call], [capture][native-capture], [build guide][native-build] | `Transport::SendRtp/SendRtcp`, stream transport configuration and `PacketReceiver` permit direct application packet delivery without PeerConnection ICE. The upstream direct-transport test demonstrates the pattern. [Transport][native-transport], [receiver][native-receiver], [test][native-direct] | Strongest control over packets and feedback. Mosh must own configuration, authenticated media protection, device integration, threads, C ABI and native artifact production. A small ABI does not make that work small. |
| GStreamer `rtpbin` + `appsrc/appsink` | RTP sessions, jitter buffering and RTCP synchronization; codecs/capture/playout plugins, WebRTC audio processing and a GCC element. Official desktop packages exist. [rtpbin][gst-rtp], [AEC][gst-aec], [GCC][gst-gcc], [distributions][gst-download] | Application buffers enter/leave explicit RTP/RTCP pads through appsrc/appsink. There is no requirement to put UDP sockets or ICE in this pipeline. [appsrc][gst-src], [appsink][gst-sink] | Most direct documented custom-carrier API and conventional packaging. Mosh must compose and maintain an AV calling pipeline rather than only adapt a transport. |
| flutter_webrtc public API | Desktop AV capture and Flutter rendering; current maintained native packaging. [Platform table][flutter-readme], [changelog][flutter-changelog] | PeerConnection/SDP/ICE and frame encryption do not provide a documented raw packet transport replacement. [PeerConnection][flutter-pc], [frame encryption][flutter-e2ee] | Exclude the unchanged public API for strict Moss carriage. A native fork/extension would become another transport integration, with the existing plugin's platform ownership and packaging to maintain. |

## RingRTC needs less media assembly, but has specific costs

The public lower factory can create a PeerConnection and expose the injectable network without using CallManager. Video input accepts I420/NV12/RGBA frames, and the observer can return decoded frame content. This establishes an integration path, not a supplied Flutter camera or child-window renderer. [Factory][ring-factory], [frame API][ring-media], [observer][ring-observer]

The inspected desktop native factory uses software VP8/VP9 video factories and native audio processing. A 720p30 CPU/thermal claim remains untested. Signal's shipped Electron path sets network injection off; source examples exercise the injection path. Source availability is weaker evidence than a deployed, supported Moss adaptation. [Native factory][ring-native], [Electron factory][ring-electron], [direct example][ring-direct]

The Rust description API supports Signal V4 reconstruction and explicit directional SRTP keys. A generic public SDP parser was not found in the inspected API. V4 construction disables DTLS, so ordinary SDP/DTLS negotiation cannot be assumed. Mosh must authenticate the selected devices and media parameters and provide the appropriate keys through its own signaling. This does not require a Signal server, but it is a lasting integration contract. [Description API][ring-sdp], [V4 reconstruction][ring-native-sdp]

`zkgroup` from Signal's libsignal is a mandatory Cargo dependency at the inspected revision. Using only low-level media objects does not remove that dependency. `libsignal-core` is a development dependency, not a separate mandatory runtime dependency. [Cargo manifest][ring-cargo]

The Rust outgoing callback returns `()`, while the matching C++ header declares `int` callbacks for SendUdp and Delete. This is a declaration mismatch, not a demonstrated runtime failure. Native SendUdp ignores the callback return and reports the full packet length, so the stock callback cannot reject an asynchronous enqueue or report later carrier transmission. Bounded queues and accurate congestion timing need an explicit solution. [Rust callbacks][ring-network], [C++ declarations][ring-header], [native send][ring-native-network]

Windows debug integration needs a specific link check. RingRTC's build script uses release prebuilts but chooses debug CRT libraries from the Cargo profile; its desktop script enables static CRT. RingRTC pins Rust 1.97.1 while Mosh currently pins 1.96.0. These are compatibility questions, not evidence of a broken build or a minimum Rust requirement. [Artifact/CRT selection][ring-package-build], [desktop build script][ring-desktop-script], [upstream toolchain][ring-toolchain], [Mosh toolchain](../../rust-toolchain.toml)

## GStreamer exposes the carrier cleanly, but leaves composition to Mosh

`rtpbin` combines RTP sessions, SSRC/payload demultiplexing and jitter buffers, and uses RTCP sender reports for synchronization. It exposes outgoing and incoming RTP/RTCP pads and SRTP encoder/decoder hooks. appsrc/appsink can bridge these packets to Moss while separate raw-frame output feeds presentation. Their queues have documented bounds; the application must choose them and preserve timestamps. [rtpbin][gst-rtp], [appsrc][gst-src], [appsink][gst-sink]

`webrtcdsp` supplies AEC, noise suppression and gain control. Echo cancellation needs the far-end `webrtcechoprobe` in the same pipeline with compatible sample rates. `rtpgccbwe` supplies GCC estimation and pacing, requires transport-wide feedback, and tells applications to connect estimated-bitrate changes to encoder targets. It does not automatically allocate one shared budget between audio and video. [AEC requirements][gst-aec], [GCC integration][gst-gcc]

Official device elements include macOS AVFoundation camera/audio, Windows Media Foundation camera and WASAPI2 audio. This removes the need to implement those capture backends, but not device selection, permissions, duplex operation or hot-unplug behavior. [macOS camera][gst-mac-camera], [macOS audio][gst-mac-audio], [Windows camera][gst-win-camera], [Windows audio][gst-win-audio]

The maintainability advantage is an application buffer/pad boundary and conventional versioned packages. The cost is our own pipeline lifecycle, audio clock/echo routing, RTP profile, encryption/key agreement, feedback-to-encoder wiring and plugin bundle. Availability of each component does not prove a good interactive call assembled from them.

## Maintenance and reproducible packaging

| Snapshot checked | Current primary evidence | Pin needed for Mosh |
| --- | --- | --- |
| RingRTC `331d601894f931337d24e9d56c68b94d28fc4555` | Version 2.72.1 pins Signal WebRTC 7871n. Checksum manifest lists macOS/Windows/Linux x64 and arm64. Desktop native target includes injectable-network source. [Versions][ring-version], [checksums][ring-checksums], [native build][ring-build] | Rust commit/lockfile, native revision and artifact checksum, features and toolchain. Source inclusion and manifest entries do not prove exported symbols or linking in the actual archives. |
| LiveKit Rust `39397b845d8b0b936a1e59882535092654ec43d7` | Lower crate is `libwebrtc` 0.3.51. A webrtc-sys 0.3.48 release was published 2026-10-07. Native builds have a desktop architecture matrix. [Manifest][lk-cargo], [release][lk-release], [builds][lk-builds] | Wrapper commit, native artifact bytes/checksum and toolchain. `.gclient` uses moving `m150_release`; `LK_CUSTOM_WEBRTC` permits another build but does not itself add a transport API. [Native checkout][lk-gclient], [build script][lk-build-script] |
| Native libwebrtc `e40a408898b7ea16e59ebc8ea96c6d42c8f8753d` | Official GN/Ninja/depot_tools development workflow covers the target hosts. [Guide][native-build] | Source and DEPS commits, build args, compiler and owned C ABI. No ready-made Mosh artifact was verified. |
| GStreamer 1.28.7 | Official Windows MSVC x64/arm64 installers, macOS universal packages, Linux packaging and project-maintained Cerbero build tooling. Android packages also exist. [Downloads][gst-download], [install guide][gst-install] | Version, compatible Rust bindings, explicit plugin set, per-host runtime libraries and checksums. Verify that the chosen bundles contain the required AEC/GCC/codec plugins. |
| flutter_webrtc `381926ca5b1bfea4e8b46743eee97c2ee9a9a72b` | Changelog lists 1.6.2+hotfix.4 dated 2026-10-07. Native manifests and macOS podspec define platform packaging. [Changelog][flutter-changelog], [native manifest][flutter-native], [podspec][flutter-pod] | Dart plugin and each host's native artifact. Versioned packaging does not establish custom-transport exports. |

LiveKit's new `livekit-capture` crate explicitly calls itself a developer preview, not ready for production. Its built-in source table lists pattern and clock sources. A custom pixel-source interface is not proof of a bundled production desktop camera implementation. [Capture README][lk-capture]

## Protocol components do not establish a complete AV engine

- str0m explicitly documents no audio/video capture, encode, decode, audio rendering or adaptive jitter buffer. It does provide bandwidth estimation, TWCC and NACK. It fails the complete engine requirement by its own feature table, not because it is Rust or lacks congestion control. [Feature table][str0m]
- libdatachannel describes itself as media transport. Its official media-sender example expects already encoded H.264 RTP and delegates camera/encoding to a GStreamer command; its streamer uses pre-encoded H.264/Opus files. These are useful transport components, but do not establish the integrated codec/capture/AEC/playout stack sought here. [Project][datachannel], [sender][datachannel-sender], [streamer][datachannel-streamer]
- webrtc-rs's official media example asks FFmpeg to produce encoded H.264/H.265 and Opus files before transmission to browser playback. That demonstrates protocol interoperability, not a native duplex AV/AEC device engine. This review did not establish a complete production client stack, and does not claim such integration is impossible. [Official example][webrtc-rs]

## Proof gates before dependency selection

1. Link the pinned candidate on macOS and Windows; check Linux. Inspect actual artifacts for the required transport symbols, reconcile callback ABI declarations and document reproducible builds.
2. Complete bidirectional audio/video through directed Moss, including feedback and relay. Prove all candidate traffic uses the carrier and no hidden DNS, ICE, STUN/TURN or socket path exits it. Authenticate selected-device/media-key binding; test rejection of stale packets.
3. Exercise microphone/speaker duplex and AEC with real devices, camera consent, device switching and teardown. Establish 720p30 CPU/latency on supported hosts rather than infer it from codec availability.
4. Bound carrier queues and propagate real send timing, loss and negotiated path capacity. Verify audio survives video overload and messaging keeps its own admitted capacity. RingRTC's enqueue callback and GStreamer's encoder-budget allocation need different solutions.
5. Transfer actual decoded frames to the child process with bounded delay. Test minimize, close, crash and recreation while the main process keeps audio and engine ownership. A parent's Flutter texture ID belongs to its view registry. [Texture contract](https://api.flutter.dev/flutter/widgets/Texture-class.html)

These are proposed acceptance gates. The review installed nothing, ran no runtime probes, changed no code or Moss sources, and made no commits. See [transport limits](issue-46-relay-media.research.md) and [engine/process details](issue-46-media-engine.research.md) for the separate investigations.

[ring-factory]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/src/webrtc/peer_connection_factory.rs#L307
[ring-audio]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/src/webrtc/audio_device_module.rs#L22
[ring-media]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/src/webrtc/media.rs#L181
[ring-observer]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/src/webrtc/peer_connection_observer.rs#L637
[ring-network]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/src/webrtc/injectable_network.rs#L149
[ring-header]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/src/webrtc_include/injectable_network.h#L19
[ring-native]: https://github.com/signalapp/webrtc/blob/25e48ee75ff1b6fcab10c6a200f233d449dd421e/ringrtc/rffi/src/peer_connection_factory.cc
[ring-native-network]: https://github.com/signalapp/webrtc/blob/25e48ee75ff1b6fcab10c6a200f233d449dd421e/ringrtc/rffi/src/injectable_network.cc#L219
[ring-build]: https://github.com/signalapp/webrtc/blob/25e48ee75ff1b6fcab10c6a200f233d449dd421e/ringrtc/rffi/BUILD.gn#L90
[ring-electron]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/src/electron.rs
[ring-direct]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/src/bin/direct.rs
[ring-sdp]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/src/webrtc/sdp_observer.rs
[ring-native-sdp]: https://github.com/signalapp/webrtc/blob/25e48ee75ff1b6fcab10c6a200f233d449dd421e/ringrtc/rffi/src/peer_connection.cc#L739
[ring-cargo]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/Cargo.toml#L73
[ring-version]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/config/version.properties
[ring-checksums]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/config/webrtc_artifact_checksums.json
[ring-package-build]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/src/rust/build.rs#L70
[ring-desktop-script]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/bin/build-desktop#L232
[ring-toolchain]: https://github.com/signalapp/ringrtc/blob/331d601894f931337d24e9d56c68b94d28fc4555/rust-toolchain
[lk-factory]: https://github.com/livekit/rust-sdks/blob/39397b845d8b0b936a1e59882535092654ec43d7/libwebrtc/src/peer_connection_factory.rs#L54
[lk-native]: https://github.com/livekit/rust-sdks/blob/39397b845d8b0b936a1e59882535092654ec43d7/webrtc-sys/src/peer_connection_factory.cpp#L160
[lk-devices]: https://github.com/livekit/rust-sdks/blob/39397b845d8b0b936a1e59882535092654ec43d7/libwebrtc/src/native/peer_connection_factory.rs#L124
[lk-builds]: https://github.com/livekit/rust-sdks/blob/39397b845d8b0b936a1e59882535092654ec43d7/.github/workflows/builds.yml#L47
[lk-cargo]: https://github.com/livekit/rust-sdks/blob/39397b845d8b0b936a1e59882535092654ec43d7/libwebrtc/Cargo.toml
[lk-release]: https://github.com/livekit/rust-sdks/releases/tag/webrtc-sys%2Fv0.3.48
[lk-gclient]: https://github.com/livekit/rust-sdks/blob/39397b845d8b0b936a1e59882535092654ec43d7/webrtc-sys/libwebrtc/.gclient#L4
[lk-build-script]: https://github.com/livekit/rust-sdks/blob/39397b845d8b0b936a1e59882535092654ec43d7/webrtc-sys/build.rs#L113
[lk-capture]: https://github.com/livekit/rust-sdks/blob/39397b845d8b0b936a1e59882535092654ec43d7/livekit-capture/README.md
[native-call]: https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/call/call.h
[native-transport]: https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/api/call/transport.h
[native-receiver]: https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/call/packet_receiver.h
[native-direct]: https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/test/direct_transport.cc
[native-capture]: https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/modules/video_capture/video_capture_factory.h
[native-build]: https://webrtc.googlesource.com/src/+/e40a408898b7ea16e59ebc8ea96c6d42c8f8753d/docs/native-code/development/README.md
[gst-rtp]: https://gstreamer.freedesktop.org/documentation/rtpmanager/rtpbin.html
[gst-src]: https://gstreamer.freedesktop.org/documentation/app/appsrc.html
[gst-sink]: https://gstreamer.freedesktop.org/documentation/app/appsink.html
[gst-aec]: https://gstreamer.freedesktop.org/documentation/webrtcdsp/webrtcdsp.html
[gst-gcc]: https://gstreamer.freedesktop.org/documentation/rsrtp/rtpgccbwe.html
[gst-download]: https://gstreamer.freedesktop.org/download/
[gst-install]: https://gstreamer.freedesktop.org/documentation/installing/index.html
[gst-mac-camera]: https://gstreamer.freedesktop.org/documentation/applemedia/avfvideosrc.html
[gst-mac-audio]: https://gstreamer.freedesktop.org/documentation/osxaudio/osxaudiosrc.html
[gst-win-camera]: https://gstreamer.freedesktop.org/documentation/mediafoundation/mfvideosrc.html
[gst-win-audio]: https://gstreamer.freedesktop.org/documentation/wasapi2/wasapi2src.html
[flutter-readme]: https://github.com/flutter-webrtc/flutter-webrtc/blob/381926ca5b1bfea4e8b46743eee97c2ee9a9a72b/README.md
[flutter-changelog]: https://github.com/flutter-webrtc/flutter-webrtc/blob/381926ca5b1bfea4e8b46743eee97c2ee9a9a72b/CHANGELOG.md
[flutter-pc]: https://github.com/flutter-webrtc/flutter-webrtc/blob/381926ca5b1bfea4e8b46743eee97c2ee9a9a72b/lib/src/native/rtc_peerconnection_impl.dart
[flutter-e2ee]: https://github.com/flutter-webrtc/flutter-webrtc/blob/381926ca5b1bfea4e8b46743eee97c2ee9a9a72b/Documentation/E2EE.md
[flutter-native]: https://github.com/flutter-webrtc/flutter-webrtc/blob/381926ca5b1bfea4e8b46743eee97c2ee9a9a72b/third_party/libwebrtc_version.ini
[flutter-pod]: https://github.com/flutter-webrtc/flutter-webrtc/blob/381926ca5b1bfea4e8b46743eee97c2ee9a9a72b/macos/flutter_webrtc.podspec
[str0m]: https://github.com/algesten/str0m/blob/393a3d238aa466ba9edc52fba823f86563642c20/README.md#L550
[datachannel]: https://github.com/paullouisageneau/libdatachannel/blob/bdc5ff28e9d3b863144c94a677ecf5bf043aaf15/README.md
[datachannel-sender]: https://github.com/paullouisageneau/libdatachannel/blob/bdc5ff28e9d3b863144c94a677ecf5bf043aaf15/examples/media-sender/README.md
[datachannel-streamer]: https://github.com/paullouisageneau/libdatachannel/blob/bdc5ff28e9d3b863144c94a677ecf5bf043aaf15/examples/streamer/README.md
[webrtc-rs]: https://github.com/webrtc-rs/webrtc/blob/7dba253753a95ea9dbb5d97b8a57de534f88c84e/examples/play-from-disk-h26x/README.md
