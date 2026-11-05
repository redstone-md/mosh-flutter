# libwebrtc engine probe (MOSH-60)

A throwaway voice-only engine on Google's libwebrtc through LiveKit's Rust
bindings. It exports the same `mosh_media_*` C ABI as `mosh-media/engine`, so
mosh-core loads it unchanged. Every packet crosses Moss through the patched
virtual network; media is DTLS-SRTP (AEAD AES-256-GCM) with the certificate
fingerprint inside the MLS-authenticated description. Findings are in
[the research note](../../docs/Proposals/call-engine-without-ringrtc.research.md).

Run Cargo from this directory: its `.cargo/config.toml` carries the link
flags libwebrtc needs on Windows and Apple targets.

```sh
node scripts/livekit-webrtc-prepare.mjs
cd mosh-probe/webrtc
cargo test --test loopback
cargo build --release
```

On Linux, LiveKit's libwebrtc needs clang 21 or later: set `CC`/`CXX` to it,
for example Chromium's own toolchain (the revision is `CR_CLANG_REVISION` in
the downloaded artifact's `webrtc.ninja`). To use a libwebrtc you built
yourself, set `LK_CUSTOM_WEBRTC` to its output directory.

Call setup through mosh-core, MLS signalling and Moss (microphone off; it
checks that the selected pair connects):

```sh
MOSH_MEDIA_ENGINE=$PWD/mosh-probe/webrtc/target/release/libmosh_webrtc_probe.so \
  node scripts/moss-test.mjs --test device_link_flow native_selected_pair -- --ignored
```

`MOSH_PROBE_RED=1` ranks RED (RFC 2198 audio redundancy) ahead of plain Opus,
the setting the research note measures for lossy links.

Voice over real Moss, with audio devices, is measured by
[media-bench](../media-bench/README.md) with `--moss`.
