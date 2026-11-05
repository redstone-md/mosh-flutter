# MOSH-60: call engine without RingRTC

Research date: 2026-11-05. Epic: MOSH-70. Probe code: `mosh-probe/webrtc`
(since MOSH-71 the engine in [mosh-media/webrtc](../../mosh-media/webrtc)),
[mosh-probe/media-bench](../../mosh-probe/media-bench), patches in
[third_party/webrtc-sys-patches](../../third_party/webrtc-sys-patches/README.md).

## Recommendation

Go ahead with MOSH-70 as planned: Google's libwebrtc (BSD) through LiveKit's
`webrtc-sys`/`libwebrtc` crates (Apache-2.0), with Mosh's own libwebrtc builds
on every platform. Nothing found blocks it:

- Moss transport needs **no change to Google's libwebrtc** (the C++ library):
  its own `PacketSocketFactory` and `NetworkManager` dependencies take a
  virtual network. The patch is to LiveKit's two binding crates, about 730
  diff lines including the new files.
- The probe engine implements the existing `mosh_media_*` ABI, so mosh-core,
  MLS signalling, device selection (ADR 0043) and Moss routing stay unchanged.
  mosh-core's real-call setup test passes with it as-is (microphone off), and
  voice crosses two real Moss nodes in the bench.
- Mouth-to-ear delay is 50–100 ms lower than RingRTC in every scenario, over
  real Moss and on emulated links, and CPU is similar. Sound returns after an
  outage within 80–95 ms. With RED it conceals less than RingRTC under heavy
  loss. MOSH-71 chose 20 ms Opus packets with RED and no DTX (see
  [measurements](#measurements)).
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

A network serves exactly one factory: the factory binds it to its network
thread, detaches it on teardown, and a second factory aborts the process.

`strace` on the loopback test shows no `socket()` call of any address family;
the test asserts `AEAD_AES_256_GCM` and a DTLS 1.3 cipher suite. The patch is
pinned like RingRTC's (`scripts/livekit-webrtc-prepare.mjs`, archive and tree
checksums). It is small enough to propose upstream to LiveKit.

## Own libwebrtc builds and platforms

`webrtc-sys` downloads LiveKit's prebuilt archive unless `LK_CUSTOM_WEBRTC`
points at another build with the same layout. LiveKit's scripts build the
`webrtc-sdk/webrtc` fork at `m150_release` (Google upstream plus LiveKit's
patches, BSD) for every target we need.

- **Linux x64, our build:** `build_linux.sh` with `rtc_use_h264=false`. Sync
  8.5 min, build 4.4 min on 16 cores (45 CPU-min), 16 GB checkout. The probe
  built against it with `LK_CUSTOM_WEBRTC` passes the loopback test and is
  what the measurements use. Its `LICENSE.md` lists only permissive components
  (no ffmpeg, no openh264).
- **Android arm64, our build:** `build_android.sh` (H.264 already off).
  Syncing the Android dependencies into the same checkout and building took
  6 min 43 s; `cargo ndk` then built the probe against it with
  `LK_CUSTOM_WEBRTC` in 35 s. The library needs only system libraries
  (`libOpenSLES`, `liblog`, `libc`, `libm`, `libdl`); libwebrtc and libc++ are
  linked in. Its `LICENSE.md` has no ffmpeg or openh264. This is the build
  MOSH-59 publishes for F-Droid; it replaces `third_party/webrtc-android-patches`.
  Not run on a device here.
- **Windows, macOS and iOS, our build:** not run here (no such hosts). They
  use the same LiveKit scripts that produce the prebuilts the CI jobs below
  pass with, so the remaining risk is CI time, not feasibility. MOSH-71 and
  MOSH-77 add those jobs.
- **All five targets with LiveKit's prebuilts:** CI (then `webrtc-probe.yml`,
  now part of [ci.yml](../../.github/workflows/ci.yml)) runs the
  loopback test on Linux, Windows and macOS and builds for Android arm64 and
  iOS arm64, all green. Windows needs the static CRT and Apple
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
the ABI as two processes and drives them as mosh-core does, joined either by
two real Moss nodes (`--moss`, the carrier of the existing `mosh-probe/media`
host) or by an emulated link with delay, random loss and a rate cap. The
`mosh-probe/media` stand itself has its own ABI and no audio path, so it
could not load the current engine or measure mouth to ear. Each peer has its
own PulseAudio server; a 50 ms 1 kHz burst enters the caller's microphone
every second and mouth-to-ear delay is the gap between its onset at that
microphone and at the callee's speaker. Calibration on one server reads
0.0 ms; across the two servers both recordings run at the same 10 ms latency.
Release builds, Linux x64, 16 cores, 30 s per run, two runs each. RingRTC is
the current `mosh-media/engine`; libwebrtc is the probe on our own libwebrtc
build. CPU includes the bench worker's 1 ms polling loop, the same for both.

Over real Moss on loopback:

| Engine | Mouth-to-ear | Bursts heard | Setup | CPU caller / callee | Moss packets sent (caller) | Moss drops |
| --- | --- | --- | --- | --- | --- | --- |
| RingRTC | 134–140 ms | 29/30 | 36 ms | 8.3 / 7.7 % | 497–509 | 0 |
| libwebrtc | 75–78 ms | 29/30 | 29–30 ms | 10.8 / 6.4 % | 1558–1560 | 0 |
| libwebrtc + RED | 76–79 ms | 29/30 | 29 ms | 10.1 / 5.8 % | 1577–1579 | 0 |

On emulated links (the 224 kbit/s row is a rate cap with a 32 KB drop-tail
queue standing in for a relay's flow budget, not a Moss relay):

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

Recovery after a 3 s outage (40 ms delay, every packet dropped; a continuous
tone replaces the bursts). "Returns" is from the end of the outage to the
speaker back at half its earlier level:

| Engine | Returns | Speaker below 10 % during the outage |
| --- | --- | --- |
| RingRTC | 144–170 ms (2 of 5 runs); 42–61 ms in the other 3 | 2.98 s; 10–60 ms in the other 3 |
| libwebrtc | 89–95 ms | 2.81–2.86 s |
| libwebrtc + RED | 78–82 ms | 2.80–2.83 s |

In three RingRTC runs its concealment never let the speaker fall below a tenth
of the earlier level, so those runs show no measurable gap rather than a faster
recovery. libwebrtc behaves the same in every run.

Reading the table:

- **Delay.** libwebrtc is 55–100 ms faster mouth to ear everywhere, 50–70 ms
  with RED. RingRTC
  configures Opus for 60 ms packets at a fixed 32 kbit/s with DTX and in-band
  FEC (`AudioEncoderConfig::default`); libwebrtc's default is 20 ms packets,
  adaptive bitrate, no DTX.
- **Setup** is offer to ICE connected. For libwebrtc that is before DTLS
  completes, so the cost ADR 0051 adds is not in this column: DTLS 1.3 needs
  one more round trip before media flows (a few tens of ms on these links,
  more on relayed paths). It was not measured separately. At 15 % loss the
  ICE checks themselves take longer.
- **Loss.** "Concealed" is not strictly comparable: RingRTC reports the last
  stats interval, libwebrtc the whole call. At 5 % loss libwebrtc conceals less;
  at 15 % RingRTC conceals about half as much: its fixed 32 kbit/s leaves Opus
  room for in-band FEC from the start, while libwebrtc's adaptive Opus adds FEC
  only after loss reports. RED (RFC 2198) closes the gap: libwebrtc offers it
  by default but ranks it after plain Opus. Ranked first, it conceals 1.5 % at
  15 % loss against RingRTC's 6 %, for 20–30 ms more delay. Use RED in MOSH-71.
- **Packet rate.** 50 packets/s is four times RingRTC's (60 ms packets plus
  DTX on this mostly silent test signal). Each packet is a Moss envelope, which
  matters on relays with per-flow budgets. 40 or 60 ms packets trade 20–40 ms
  of delay for overhead. MOSH-71 kept 20 ms without DTX: on the bench, 40 ms
  packets added delay and concealment, and DTX cost RED most of its gain.
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
| MOSH-71 voice desktop↔desktop | 6–8 | Move the probe into `mosh-media/engine` behind a developer flag (its ABI and carrier replace the RingRTC ones, so no copy remains); CI builds and caches our libwebrtc for Windows, macOS, Linux; Opus frame size and RED; engine version in the call protocol with an "update Mosh" outcome; relay test |
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
