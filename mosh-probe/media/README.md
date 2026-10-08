# Native media feasibility probe for issue 46

This is an isolated RingRTC candidate, not video-call support in the application.
Each host process owns one actual Moss node and one native WebRTC engine. The
engine is a separate shared library loaded into that same process, so its Rust
dependency graph stays separate from OpenMLS. Native media and ICE packets go
through directed Moss packets; ICE servers are empty and the engine receives
only virtual interfaces.
The fixture also disables Moss DHT/LAN discovery and trackers; its controller
connects the two loopback nodes explicitly. Application discovery stays unchanged.

The controller uses trusted parent/worker pipes for test negotiation. It installs
fresh, random, directional AES-256-GCM SRTP keys and keeps their values out of
reported measurements. This does **not** prove authenticated device selection,
call coordination, camera consent or production key exchange.

## Build and run

From the repository root, with Node, Git, Cargo, C/C++ build tools and `protoc`:

```sh
node scripts/moss-prepare.mjs
node scripts/ringrtc-prepare.mjs
cargo build --manifest-path mosh-probe/media/Cargo.toml --locked -j 2
cargo build --manifest-path mosh-probe/media-host/Cargo.toml --locked -j 2
node scripts/media-probe.mjs --duration 60
node scripts/media-probe.mjs --duration 15 --tamper-key
```

Use debug builds on Windows, as required by the integration policy. On macOS,
run both Apple Silicon and Intel builds where available. Build tools and the
OS's native audio backend must be installed. The probe inherits normal audio
device selection; permission refusal and a headless machine can prevent capture.

Custom build output directories are supported:

```sh
node scripts/media-probe.mjs --executable /path/to/mosh-media-probe --engine /path/to/libmosh_media_probe.so --duration 60
```

The engine filename is `mosh_media_probe.dll` on Windows and
`libmosh_media_probe.dylib` on macOS. The executable has `.exe` on Windows.
The synthetic source emits changing I420 luma at a requested 1280×720/30 fps.
The engine may adapt its actual transmitted resolution and frame rate.

## Interpreting results

Every five seconds the runner emits JSON with decoded counts, received audio
packet rate/energy, actual video resolution/rate, codec, encoder/decoder
implementation, loss, and carrier drops/errors/send duration. A normal run
passes its narrow transport check when both peers decode video and receive
audio packets. Silence can produce zero energy; packet receipt does not prove
microphone capture or audible playback. The tampered-key run passes only when
the callee cannot decode the caller's video or receive its audio, while the
reverse direction still receives both. This is a negative SRTP authentication check.

The two fixture queues each hold at most 128 packets; the Moss unclaimed inbox
holds at most 256. Carrier packets are capped at 2007 bytes including the test
header and queued packets older than 50 ms are dropped. These are probe limits,
not measured production scheduling budgets. `max_send_ms` measures the duration
of `Moss_SendToPeer`, not end-to-end media latency or actual wire completion.
On a started direct node, Moss itself admits the envelope to its bounded
per-peer outbound queue. The fixture counters do not measure that queue's age
or subsequent write/drop result.
The pinned Moss API can spend five seconds opening a relay. Native injected
socket timestamps acknowledge queue admission before that call completes.

The fixture connects two installations on loopback. It does not exercise relay,
camera capture, frame IPC, Flutter rendering or a remote desktop. Do not call a
passing synthetic run sustained 720p30 acceptance. Record actual measurements
and physical-host results using the [implementation plan](../../docs/Proposals/issue-46-video-calls.plan.md).

Moss's packet callback reports a **claimed** sender key. The probe filters by
that key, but its media authentication comes from the SRTP keys selected through
trusted pipes. Production controls must authenticate linked-device identity;
the callback metadata cannot replace that proof.

## Focused transport regression

```sh
cargo test --manifest-path mosh-core/Cargo.toml --test directed_packets
```

This uses separate real Moss processes and checks bidirectional directed
payloads plus existing stream delivery in both callback-registration orders.
No default application build or dependency is switched to this candidate.

For a Linux native socket check without loading Moss:

```sh
MOSH_MEDIA_ENGINE=mosh-probe/media/target/debug/libmosh_media_probe.so strace -f -e trace=network mosh-probe/media-host/target/debug/mosh-media-probe factory
```

See the [recorded results and open adoption gates](../../docs/Proposals/issue-46-native-media.results.md).
