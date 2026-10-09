# Issue 46: hardware encoding in Discord, Telegram and candidate engines

Research date: 2026-10-08. Primary documentation/source review only. No installs, builds or runtime probes. Camera 1:1 video is the current Mosh scope; screen sharing is separate.

## Finding

Hardware encoding is an established optimization, particularly in Discord Go Live and Telegram's Darwin implementation. The evidence does not support "all Telegram/Discord video calls use hardware encoding" or a uniform desktop implementation. The codec negotiated with the receiver, platform factory, build options, driver and actual session all matter.

For Mosh, keep software acceptable only after real 720p30, sustained thermal, latency and UI checks, as agreed. Preserve an encoder-factory boundary so hardware support can be added without changing Moss or call ownership. Hardware capability in an unrelated app is not proof that our chosen native artifact enables it.

## Encoding, decoding and capture are different evidence

- Encoding compresses locally captured frames for sending. This is the path relevant to outgoing camera CPU and thermal load.
- Decoding expands received video for presentation. Hardware decoder evidence does not establish a hardware encoder.
- Capture and GPU-resident frames can reduce copies before encoding. GPU capture, accelerated rendering and hardware AES encryption do not prove hardware video compression.

## Discord

| Evidence and scope | What it establishes | What remains unknown |
| --- | --- | --- |
| March 2024 Go Live architecture post | Go Live negotiates a codec the sender can encode and viewers can decode. It prefers available GPU encoder/decoder implementations. VP8/H.264 and platform-specific HEVC/AV1 are discussed. Capture has OS-specific fallbacks. [Architecture][discord-overview] | This describes application/game/screen streaming, not a complete platform-by-platform camera-call encoder/default table. |
| May 2024 AMD Go Live engineering post | Discord uses custom capture/encoding code integrated with OS/video drivers. The measured AMD Windows streaming path needed keyframe, rate-control and frame-dropper fixes despite hardware acceleration. [AMD investigation][discord-amd] | Hardware availability alone does not guarantee stable frame rate or quality. These results are not camera-call measurements or Mosh targets. |
| December 2025 release notes | AMD GPU hardware video encoding through VAAPI on Linux is explicitly supported; Steam Deck Go Live gained zero-copy encoding. macOS/iOS rate-control improvements are separately mentioned. [Release notes][discord-linux] | No claim that every Linux GPU, codec or camera call uses this path. The macOS note does not identify its encoding API. |
| January 2026 Windows codec documentation | Discord uses OS codecs and an AVC encoder for camera and Go Live. It chooses a codec supported by participants. [Windows codec guide][discord-codecs] | OS codec selection alone does not establish GPU versus software operation in every camera call. |
| Current Voice & Video support documentation | Hardware Acceleration is an exposed Video setting and disabling it is an official troubleshooting option. [Settings][discord-settings], [troubleshooting][discord-troubleshooting] | The setting is not a guarantee that a particular encode session is hardware-backed. The previously linked Video Codec FAQ now returns 404; no current H.264-specific developer API contract was established. |

The Go Live post separately describes hardware decode, RTP transport and playback. Its GPU encoding claim is valid for that streaming architecture. It cannot be expanded into "all 1:1 camera video is GPU encoded on macOS, Windows and Linux." Discord's server relay architecture is also unrelated to the requirement that Mosh packets use Moss.

## Telegram snapshots and dependency pins

The latest stable Telegram Desktop release inspected is [v7.2.9][td-release], published 2026-09-17, commit `fb2e33209517e1a34637d837bfadb3783f2fd59c`. A separate current development snapshot is `6ec5014a92c4580841a043c440d65e8fc605ff78`. Do not treat development changes as released behavior.

| Dependency | v7.2.9 source pin | Development source pin |
| --- | --- | --- |
| `Telegram/ThirdParty/tgcalls` gitlink | `2faee3b5524f54d56c91c2058c00e11c656a74b3` | `1c236c09f8d8569fead14bd68000618a52051225` |
| `Telegram/lib_webrtc` gitlink | `52636e86eaa493de670daf71959d000b281bd153` | Same |
| Actual WebRTC fork `desktop-app/tg_owt` | Preparation script checks out `89df288dd6ba5b2ec95b3c5eaf1e7e0c3a870fc4` | Preparation script checks out `d1cf250ea73de26c4c1f0a3c8173eb2648efbb04` |

The gitlinks come from the [release tree][td-release-tree] and [development tree][td-dev-tree]; the actual WebRTC checkout comes from the [release preparation script][td-release-prepare] and [development script][td-dev-prepare]. `lib_webrtc` is Telegram's platform integration wrapper, not the actual upstream WebRTC source pin.

The desktop encoder factories are identical between these tgcalls snapshots. The inspected `tg_owt` internal encoder factory is also identical. The V2 initializer differs in unrelated custom-parameter helper code; its native-network selection remains the same.

## Telegram encoding paths

| Path | Concrete source behavior | Selection/fallback limit |
| --- | --- | --- |
| Telegram Desktop macOS | Its CMake target removes the generic desktop platform and retains Darwin. Darwin wraps `TGRTCDefaultVideoEncoderFactory`; V2 requests `makeVideoEncoderFactory(true)`. [Build selection][td-tgcalls-build], [Darwin factory][tg-darwin], [V2 factory][tg-v2] | This is actual desktop platform selection, not an assumption based on Telegram iOS. A negotiated codec still determines which encoder runs. |
| Darwin H.264 | The hardware-preferred factory creates `TGRTCVideoEncoderH264`. It creates a VideoToolbox compression session with `EnableHardwareAcceleratedVideoEncoder=true` on macOS and reads/logs `UsingHardwareAcceleratedVideoEncoder`. [Factory branch][tg-darwin-encoder], [session][tg-vt-h264] | Apple's Enable key allows hardware when available; it does not require it. Session creation errors return a codec error. No blanket automatic mid-call codec fallback was verified. [Apple Enable][apple-enable], [Apple Require][apple-require] |
| Darwin H.265 | A separate VideoToolbox encoder exists with hardware enabled and low-latency settings. Darwin's capability policy permits H.265 on macOS arm64 and rejects it on x86_64; its H.264 capability policy does the opposite. VP8/VP9 remain advertised options. [Platform policy][tg-darwin], [H.265 session][tg-vt-h265] | A codec appearing in a factory is not enough. `supportsEncoding` filters the offered choices, and the receiver must support the negotiated codec. |
| Telegram Desktop Windows/Linux | Generic `DesktopInterface` returns `CreateBuiltinVideoEncoderFactory` and ignores the hardware-preference argument. The pinned `tg_owt` factory uses libvpx VP8/VP9, OpenH264 and conditionally libaom AV1 implementations. OpenH264 creates a Wels software encoder. [Desktop factory][tg-desktop], [pinned factory][owt-encoder], [OpenH264 implementation][owt-h264] | The available factory formats exceed the generic platform's permitted send list, which explicitly accepts H.264/VP8. GPU-accelerated capture or video playback does not alter this encoding selection. |
| Conditional UWP branch | `TGCALLS_UWP_DESKTOP` selects H264MF encoder/decoder factories in the generic platform source. [Conditional code][tg-desktop] | This is not evidence that normal Telegram Desktop builds use it. The inspected desktop target does not enable this definition; its normal branch and pinned factory above are the verified path. |
| Older versus V2 call implementations | V2 requests hardware preference explicitly; older `MediaManager` invokes the factory with its default arguments. Codec sorting consults platform support and preferred codecs. [Older factory call][tg-media], [sorting][tg-codecs] | One factory call/default cannot be generalized to every historical/protocol implementation. |

Darwin also has dedicated VideoToolbox decoders and camera/capture code. Those are separate functions and are not evidence about Windows/Linux encoding. The source proves available and requested paths, not the hardware flag, negotiated codec, CPU cost or thermal result of an actual live session.

## Does tgcalls become the better Moss engine?

It becomes a credible additional candidate, but the inspected public descriptor is insufficient to make it a superior ready-made choice.

`DirectConnectionChannel` exposes packet send and incoming-packet subscription/removal. `DirectNetworkingImpl` connects an `RtpTransport` with RTCP mux and SCTP to a custom `DirectPacketTransport`. Its implementation forwards packets through that channel and provides an encrypted framing/hello/keepalive protocol; its ICE candidate setters are empty. This is a design for a complete alternative packet carrier, not merely camera frame input. [Channel API][tg-channel], [transport implementation][tg-direct]

However, `InstanceV2Impl` only stores `descriptor.directConnectionChannel`. Initialization unconditionally constructs `NativeNetworkingImpl`; it does not select `DirectNetworkingImpl` or pass the channel to that configuration. The same behavior is present in the release snapshot. The desktop build compiles DirectNetworkingImpl, but compilation does not make the descriptor field an active transport switch. [Development initializer][tg-v2], [release initializer][tg-v2-release], [build sources][td-tgcalls-build]

The source-level direct path would avoid a mandatory TURN server if it were wired and validated. The shipped native selection still manages its own ICE/socket/relay route. Empty server configuration or P2P disabled is not proof that media enters Moss. A Mosh integration would need an owned adapter/library change and a complete confinement test.

The direct channel's `sendPacket` returns void; the packet transport reports send timing at callback submission and has an `assert(false)` in its encryption service callback. `DirectRtpTransport::IsSrtpActive` returns true while the implementation supplies its own encrypted connection framing. These details require validation of congestion timing, bounded queues and authenticated encryption/key ownership, rather than treating the path as standard DTLS-SRTP. [Direct transport][tg-direct]

Desktop tgcalls builds against `tg_owt`, FFmpeg, OpenSSL, RNNoise and zlib through Telegram's CMake integration. It offers audio-device injection, decoded video sinks and capture interfaces, but no independent versioned macOS/Windows/Linux native artifact set was established in this review. Its Windows/Linux encoding path does not solve cross-platform hardware encoding by itself. [Desktop dependencies][td-tgcalls-build], [descriptor/media API][tg-instance]

My judgement remains to validate RingRTC first under the [existing gates](issue-46-media-candidates.research.md). tgcalls is useful prior art and an alternate complete-media candidate if owning its C++ build and missing transport selection is acceptable. Its Darwin hardware factories improve that alternative's macOS capability, but do not outweigh the transport/packaging work without a demonstrated integration.

## Implications for Mosh acceptance

1. Record the negotiated codec, actual encoder implementation and hardware/software state at runtime. A user-visible indicator must reflect those facts rather than the OS or GPU model.
2. Exercise outgoing and incoming 720p30 separately, then duplex. Measure delivered frame cadence, encode/decode latency, CPU, sustained thermals and Flutter UI responsiveness on actual macOS/Windows hosts; preserve Linux checks.
3. Prefer hardware only where the built factory, driver and negotiated profile support it. Confirm behavior when session creation fails, hardware resources are busy, device changes occur or a software path is selected. A list of alternate codecs does not prove automatic recovery.
4. Preserve audio under video overload and carrier rate limits. Hardware encoding saves compute, not relay bandwidth, and must still react to the negotiated Moss budget.
5. Keep codec/capture selection inside the main-process media owner. Child rendering and GPU frame transfer are separate optimization decisions and must survive child recreation.

These are proposed checks, not benchmark results or a dependency change. Context7 did not have a matching tgcalls API package; source was used directly. Context7 Apple documentation and Apple's primary VideoToolbox reference were consulted for the meaning of hardware enable/require settings.

[discord-overview]: https://discord.com/blog/how-it-all-goes-live-an-overview-of-discords-streaming-technology
[discord-amd]: https://discord.com/blog/from-blocky-to-brilliant-improving-video-quality-on-discord-go-live-on-amd-gpus
[discord-linux]: https://discord.com/blog/discord-patch-notes-december-8-2025
[discord-codecs]: https://support.discord.com/hc/en-us/articles/37976724130711-Microsoft-Store-Codecs-for-Discord
[discord-settings]: https://support.discord.com/hc/en-us/articles/33030151293079-Discord-Voice-Video-Streaming-Guide
[discord-troubleshooting]: https://support.discord.com/hc/en-us/articles/360045138471-Discord-Voice-and-Video-Troubleshooting-Guide
[td-release]: https://github.com/telegramdesktop/tdesktop/releases/tag/v7.2.9
[td-release-tree]: https://github.com/telegramdesktop/tdesktop/tree/fb2e33209517e1a34637d837bfadb3783f2fd59c/Telegram
[td-dev-tree]: https://github.com/telegramdesktop/tdesktop/tree/6ec5014a92c4580841a043c440d65e8fc605ff78/Telegram
[td-release-prepare]: https://github.com/telegramdesktop/tdesktop/blob/fb2e33209517e1a34637d837bfadb3783f2fd59c/Telegram/build/prepare/prepare.py#L1731
[td-dev-prepare]: https://github.com/telegramdesktop/tdesktop/blob/6ec5014a92c4580841a043c440d65e8fc605ff78/Telegram/build/prepare/prepare.py#L1785
[td-tgcalls-build]: https://github.com/telegramdesktop/tdesktop/blob/6ec5014a92c4580841a043c440d65e8fc605ff78/Telegram/cmake/lib_tgcalls.cmake#L233
[tg-darwin]: https://github.com/TelegramMessenger/tgcalls/blob/1c236c09f8d8569fead14bd68000618a52051225/tgcalls/platform/darwin/DarwinInterface.mm#L69
[tg-darwin-encoder]: https://github.com/TelegramMessenger/tgcalls/blob/1c236c09f8d8569fead14bd68000618a52051225/tgcalls/platform/darwin/TGRTCDefaultVideoEncoderFactory.mm#L107
[tg-vt-h264]: https://github.com/TelegramMessenger/tgcalls/blob/1c236c09f8d8569fead14bd68000618a52051225/tgcalls/platform/darwin/TGRTCVideoEncoderH264.mm#L643
[tg-vt-h265]: https://github.com/TelegramMessenger/tgcalls/blob/1c236c09f8d8569fead14bd68000618a52051225/tgcalls/platform/darwin/TGRTCVideoEncoderH265.mm#L414
[tg-desktop]: https://github.com/TelegramMessenger/tgcalls/blob/1c236c09f8d8569fead14bd68000618a52051225/tgcalls/platform/tdesktop/DesktopInterface.cpp#L16
[tg-media]: https://github.com/TelegramMessenger/tgcalls/blob/1c236c09f8d8569fead14bd68000618a52051225/tgcalls/MediaManager.cpp#L322
[tg-codecs]: https://github.com/TelegramMessenger/tgcalls/blob/1c236c09f8d8569fead14bd68000618a52051225/tgcalls/CodecSelectHelper.cpp#L26
[owt-encoder]: https://github.com/desktop-app/tg_owt/blob/89df288dd6ba5b2ec95b3c5eaf1e7e0c3a870fc4/src/media/engine/internal_encoder_factory.cc#L32
[owt-h264]: https://github.com/desktop-app/tg_owt/blob/89df288dd6ba5b2ec95b3c5eaf1e7e0c3a870fc4/src/modules/video_coding/codecs/h264/h264_encoder_impl.cc#L253
[tg-instance]: https://github.com/TelegramMessenger/tgcalls/blob/1c236c09f8d8569fead14bd68000618a52051225/tgcalls/Instance.h#L219
[tg-channel]: https://github.com/TelegramMessenger/tgcalls/blob/1c236c09f8d8569fead14bd68000618a52051225/tgcalls/DirectConnectionChannel.h#L11
[tg-direct]: https://github.com/TelegramMessenger/tgcalls/blob/1c236c09f8d8569fead14bd68000618a52051225/tgcalls/v2/DirectNetworkingImpl.cpp#L34
[tg-v2]: https://github.com/TelegramMessenger/tgcalls/blob/1c236c09f8d8569fead14bd68000618a52051225/tgcalls/v2/InstanceV2Impl.cpp#L1039
[tg-v2-release]: https://github.com/TelegramMessenger/tgcalls/blob/2faee3b5524f54d56c91c2058c00e11c656a74b3/tgcalls/v2/InstanceV2Impl.cpp#L1055
[apple-enable]: https://developer.apple.com/documentation/videotoolbox/kvtvideoencoderspecification_enablehardwareacceleratedvideoencoder
[apple-require]: https://developer.apple.com/documentation/videotoolbox/kvtvideoencoderspecification_requirehardwareacceleratedvideoencoder
