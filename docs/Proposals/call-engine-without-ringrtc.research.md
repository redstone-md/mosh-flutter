# MOSH-60: call engine without RingRTC

Research date: 2026-11-05. Epic: MOSH-70. Probe code: [mosh-probe/webrtc](../../mosh-probe/webrtc),
[mosh-probe/media-bench](../../mosh-probe/media-bench), patches in
[third_party/webrtc-sys-patches](../../third_party/webrtc-sys-patches/README.md).

## Recommendation

Go ahead with MOSH-70 as planned: Google's libwebrtc (BSD) through LiveKit's
`webrtc-sys`/`libwebrtc` crates (Apache-2.0), with Mosh's own libwebrtc builds
on every platform. Nothing found blocks it:

- Moss transport works with a ~500-line patch to the bindings and **no patch to
  libwebrtc**: libwebrtc's own `PacketSocketFactory` and `NetworkManager`
  dependencies take a virtual network.
- The probe engine implements the existing `mosh_media_*` ABI, so mosh-core,
  MLS signalling, device selection (ADR 0043) and Moss routing stay unchanged.
  The real-call test over Moss passes with it as-is.
- On an identical emulated link it has 50–90 ms lower mouth-to-ear delay than
  RingRTC in every scenario and similar CPU. With RED it also conceals less
  under heavy loss. Packet rate (4× RingRTC's) is the one setting MOSH-71 must
  tune (see [measurements](#measurements)).
- One protocol change: SRTP keys come from DTLS whose certificate fingerprint
  MLS authenticates, because upstream libwebrtc has no SDES since M123
  ([ADR 0051](../ADR/0051-dtls-srtp-with-mls-authenticated-fingerprints.md)).
  ADR 0044's boundaries (one native engine, all media over Moss, frame IPC) hold.

## Network injection without forking libwebrtc

LiveKit's factory hard-wires the network thread's real socket server and
exposes no `PacketSocketFactory`, `NetworkManager` or `PortAllocator`
(`webrtc-sys/src/peer_connection_factory.cpp`). libwebrtc m150 accepts both as
`PeerConnectionFactoryDependencies`, so the patch adds, inside `webrtc-sys`:

- `VirtualNetwork`: one IPv4 interface (`192.0.2.1`/`.2`, as RingRTC used),
  UDP sockets only. `SendTo` hands the packet to a Rust closure and reports
  `SentPacketInfo` so transport-wide congestion control keeps working;
  `receive()` posts incoming packets to the network thread. TCP sockets are
  refused and DNS lookups fail.
- A `NetworkManagerBase` that lists only that interface, so ICE gathers one
  host candidate and never enumerates adapters.
- `create_peer_connection_factory_with_network`, which also restricts SRTP to
  AEAD profiles, and the safe wrappers in `libwebrtc`
  (`PeerConnectionFactory::with_virtual_network`).

`strace` on the loopback test shows no `socket()` call of any address family.
The patch is pinned like RingRTC's (`scripts/livekit-webrtc-prepare.mjs`,
archive and tree checksums). It is small enough to propose upstream to LiveKit.

## Own libwebrtc builds and platforms

`webrtc-sys` downloads LiveKit's prebuilt archive unless `LK_CUSTOM_WEBRTC`
points at another build with the same layout. LiveKit's scripts build the
`webrtc-sdk/webrtc` fork at `m150_release` (Google upstream plus LiveKit's
patches, BSD) for every target we need.

- Built here from source with `build_linux.sh` and `rtc_use_h264=false`: sync
  8.5 min, build 4.4 min on 16 cores (45 CPU-min), 16 GB checkout. The probe
  built against it passes the loopback test and is what the measurements use.
  Its `LICENSE.md` lists only permissive components (no ffmpeg, no openh264).
- CI ([webrtc-probe.yml](../../.github/workflows/webrtc-probe.yml)) runs the
  loopback test on Linux, Windows and macOS and builds for Android arm64 and
  iOS arm64 against LiveKit's prebuilts. Windows needs the static CRT and Apple
  targets `-ObjC` (`mosh-probe/webrtc/.cargo/config.toml`), as in LiveKit.
- Linux needs clang 21 or newer for libwebrtc's hermetic libc++. CI downloads
  LLVM 21; locally Chromium's pinned clang works.
- Prebuilts exist for win x64/arm64, mac x64/arm64, linux x64/arm64, Android
  arm/arm64/x64 and iOS device/arm64 simulator. No x64 iOS simulator.

For MOSH-59 (F-Droid) the Android build must be ours and published, which this
path supports; the desktop and Apple builds should be ours too, to drop ffmpeg
and openh264 (below). Build them in CI once per libwebrtc bump and store the
archives as release assets.

## What the engine takes from RingRTC and what replaces it

| RingRTC piece | Replacement |
| --- | --- |
| `InjectableNetwork`, virtual interface, `MV1` carrier framing | `VirtualNetwork` (patch above); framing and ports unchanged |
| `ConnectionParametersV4` protobuf, `offer_from_v4`/`answer_from_v4` | The SDP itself in `Description.parameters` (≤16 KB, already MLS-authenticated) |
| `disable_dtls_and_set_srtp_key`, `keys.rs` X25519/HKDF | DTLS-SRTP, fingerprint in the authenticated SDP, `AEAD_AES_256_GCM` ([ADR 0051](../ADR/0051-dtls-srtp-with-mls-authenticated-fingerprints.md)) |
| ICE candidates via `add_ice_candidate_from_sdp` | `IceCandidate::parse(mid, index, sdp)`, same tick exchange |
| `StatsObserver` snapshots | `PeerConnection::get_stats()` (standard RTCStats: inbound/outbound RTP, remote-inbound RTT, transport DTLS state) |
| Audio devices via Cubeb (desktop), `set_audio_*_enabled` | libwebrtc's platform audio module through LiveKit's `AdmProxy`: device lists and selection by GUID, `set_adm_recording_enabled`/`set_adm_playout_enabled` |
| Android: Signal's factory patch plus WebRTC's Android ADM | LiveKit's Android ADM (`CreateAndroidAudioDeviceModule`) and JNI init in `webrtc-sys`; our Android build replaces `third_party/webrtc-android-patches` |
| `set_send_rates` | `PeerConnection::set_bitrate` |
| `configure_audio_encoders` (Opus settings) | Codec preferences and SDP `fmtp`; RED for loss (see below) |
| `VideoSource.push_frame` RGBA, `adapt_output_format` | `NativeVideoSource::capture_frame` (I420 conversion via `yuv_helper`) and sender encoding parameters (`scale_resolution_down_by`, `max_framerate`); MOSH-72 |
| `handle_incoming_video_frame` | `NativeVideoStream` on the remote track; MOSH-72 |
| Hardware codecs | LiveKit's encoder/decoder factories: VideoToolbox on Apple, MediaCodec on Android; Windows software only (as today) |

The legacy iOS voice pipeline (`voice_call_runtime`, Opus over MLS frames) has
no counterpart; MOSH-77 moves iOS to this engine and MOSH-76 deletes it.

## Measurements

[media-bench](../../mosh-probe/media-bench/README.md) runs either engine behind
the ABI as two processes joined by an emulated link and drives them as
mosh-core does. Each peer has its own PulseAudio server; a 50 ms 1 kHz burst
enters the caller's microphone every second and mouth-to-ear delay is the gap
between its onset at that microphone and at the callee's speaker
(calibration: 0.0 ms). Release builds, Linux x64, 16 cores, 30 s per run, two
runs each. RingRTC is the current `mosh-media/engine`; libwebrtc is the probe
on our own libwebrtc build.

| Link (one-way delay, random loss, cap) | Engine | Mouth-to-ear | Bursts heard | Concealed | Setup | CPU caller / callee | Packets/s |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 20 ms | RingRTC | 164–170 ms | 29/30 | 0 % | 109–128 ms | 9.0 / 8.0 % | 12 |
| 20 ms | libwebrtc | 93–99 ms | 29/30 | 0–0.5 % | 83–90 ms | 10.8 / 6.4 % | 50 |
| 40 ms, 5 % | RingRTC | 190–195 ms | 29/30 | 6–12 % | 188–222 ms | 9.6 / 8.7 % | 12 |
| 40 ms, 5 % | libwebrtc | 120–123 ms | 29/30 | 3.8–4.7 % | 212–235 ms | 11.8 / 6.9 % | 50 |
| 60 ms, 1 %, 224 kbit/s (relay budget) | RingRTC | 232–233 ms | 29/30 | 0 % | 248–251 ms | 10.5 / 8.8 % | 12 |
| 60 ms, 1 %, 224 kbit/s (relay budget) | libwebrtc | 131–145 ms | 29/30 | 1.2–1.4 % | 245–275 ms | 11.5 / 6.6 % | 50 |
| 40 ms, 15 % | RingRTC | 195–208 ms | 29/30 | 6 % | 199–226 ms | 9.5 / 8.5 % | 12 |
| 40 ms, 15 % | libwebrtc | 116–117 ms | 29/30 | 11.5 % | 318–331 ms | 10.9 / 6.3 % | 50 |
| 40 ms, 5 % | libwebrtc + RED | 133–142 ms | 29/30 | 0.1–0.3 % | 198–237 ms | 11.8 / 7.3 % | 50 |
| 60 ms, 1 %, 224 kbit/s (relay budget) | libwebrtc + RED | 164–165 ms | 29/30 | 0.1 % | 227–250 ms | 11.0 / 6.5 % | 50 |
| 40 ms, 15 % | libwebrtc + RED | 144–147 ms | 29/30 | 1.4–1.5 % | 185–187 ms | 11.7 / 6.7 % | 50 |

"libwebrtc + RED" ranks RED ahead of Opus (`MOSH_PROBE_RED=1` in the probe), as
Chrome does with its RED field trial. Received audio payload goes from about
10 to 20 kbit/s, still below RingRTC's fixed 32 kbit/s.

Reading the table:

- **Delay.** libwebrtc is 70–95 ms faster mouth to ear everywhere. RingRTC
  configures Opus for 60 ms packets at a fixed 32 kbit/s with DTX and in-band
  FEC (`AudioEncoderConfig::default`); libwebrtc's default is 20 ms packets,
  adaptive bitrate, no DTX.
- **Setup** (offer to ICE connected, before DTLS completes for libwebrtc) is
  within noise except at 15 % loss, where lost DTLS flights cost a
  retransmission. Add the DTLS round trips on relayed paths (ADR 0051).
- **Loss.** "Concealed" is not strictly comparable: RingRTC reports the last
  stats interval, libwebrtc the whole call. At 5 % loss libwebrtc conceals less;
  at 15 % RingRTC conceals about half as much: its fixed 32 kbit/s leaves Opus
  room for in-band FEC from the start, while libwebrtc's adaptive Opus adds FEC
  only after loss reports. RED (RFC 2198) closes the gap: libwebrtc offers it
  by default but ranks it after plain Opus. Ranked first, it conceals 1.5 % at
  15 % loss against RingRTC's 6 %, for 20–30 ms more delay. Use RED in MOSH-71.
- **Packet rate.** 50 packets/s is four times RingRTC's (60 ms packets plus
  DTX on this mostly silent test signal). Each packet is a Moss envelope, which
  matters on relays with per-flow budgets. Choose packet size and DTX in
  MOSH-71: 40 or 60 ms packets trade 20–40 ms of delay for overhead.
- **CPU** is the same order of magnitude; the caller side costs slightly more,
  the callee less.
- **Not covered here:** echo cancellation and noise suppression quality need a
  physical-device check (both engines run libwebrtc's APM; LiveKit's Linux,
  Windows and macOS audio modules are upstream's). Video, PiP and the camera
  path are MOSH-72.

## Licenses

- `webrtc-sys`, `libwebrtc`, `webrtc-sys-build`: Apache-2.0. Their dependencies
  (cxx, tokio, parking_lot, serde_json, thiserror, jni, rtrb, lazy_static and,
  at build time, reqwest, zip, scratch, fs2) are MIT or MIT/Apache-2.0.
- libwebrtc and its bundled components: BSD-style, ISC, Apache-2.0 and zlib
  (`LICENSE.md` of our build: webrtc, abseil, boringssl, dav1d, libaom, libvpx,
  opus, libsrtp, libyuv, rnnoise, protobuf, perfetto, zlib and others).
- LiveKit's **desktop** prebuilts include ffmpeg (LGPL-2.1+) and openh264 for
  H.264. Our builds use `rtc_use_h264=false`; H.264 on Apple and Android comes
  from the platform encoders, which need neither. The iOS and Android prebuilts
  already contain neither.
- Nothing GPL/AGPL remains in the engine. MOSH-73 still has to confirm the full
  shipped tree (Flutter plugins, media_kit) and add the App Store exception.

## Slices and estimates

| Slice | Days | Notes |
| --- | --- | --- |
| MOSH-71 voice desktop↔desktop | 6–8 | Turn the probe into `mosh-media/engine` behind a developer flag; CI builds and caches our libwebrtc for Windows, macOS, Linux; Opus frame size and RED; engine version in the call protocol with an "update Mosh" outcome; relay test |
| MOSH-72 video | 5–7 | `NativeVideoSource`/`NativeVideoStream`, RGBA↔I420, budget-driven resolution and frame rate, camera and PiP paths |
| MOSH-75 Android | 6–9 | Our Android libwebrtc build (also for MOSH-59), JNI init, Android audio module with the existing AudioManager routing, Camera2 adapter |
| MOSH-76 default, delete RingRTC and the legacy voice pipeline | 3–4 | Remove `third_party/ringrtc*`, `webrtc-android-patches`, `keys.rs`, `voice_call_runtime`; notices |
| MOSH-77 iOS | 7–10 | iOS build and packaging, VoiceProcessingIO audio module, camera, background audio rules |
| MOSH-73 license audit | 1–2 | Whole shipped tree, LICENSE exception |

About 28–40 days in total, the largest unknowns being iOS audio session
behaviour and Android device variety.

## Decisions recorded

- [ADR 0051](../ADR/0051-dtls-srtp-with-mls-authenticated-fingerprints.md):
  DTLS-SRTP with MLS-authenticated fingerprints replaces Mosh-derived SRTP keys.
- ADR 0044 is unchanged: still one native engine, all media over Moss, the same
  ABI and frame IPC.
