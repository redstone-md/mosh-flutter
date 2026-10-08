# Isolated RingRTC candidate

`node scripts/ringrtc-prepare.mjs` reconstructs RingRTC 2.72.1 from the commit,
archive checksum and complete patched-tree checksum in [source.json](source.json).
It uses the same locked, atomic source preparation as OpenMLS. `--offline` uses
the verified archive cache. Existing local source edits are refused.

The application does not depend on this candidate. The feasibility library is
under [mosh-probe/media](../../mosh-probe/media/Cargo.toml); its separate host
loads it in the same process as Mosh's real Moss adapter. Keeping separate Cargo
graphs avoids the incompatible `hax-lib` requirements in RingRTC's mandatory
libsignal dependencies and Mosh's OpenMLS stack. This is a candidate packaging
boundary, not an adopted application engine.

## Local patches

[mosh.patch](mosh.patch) contains three changes against the pinned upstream:

- Match Rust injected-network send/delete return types to the C++ `int` ABI.
  This does not add transport completion feedback: native send time is still
  recorded when a packet enters the fixture queue.
- Keep the optional outgoing video track alive through `Rust_createPeerConnection`.
  The upstream consuming closure released its last reference before the native
  call. The Linux probe reproduced a segmentation fault; borrowing with `as_ref`
  removes that premature release.
- Put downloaded/extracted native artifacts in Cargo's `OUT_DIR`. Builds no
  longer change the verified source hash or share native output between targets.

The upstream build script pins and verifies the Signal WebRTC `7871n` archive.
The candidate's Cargo lockfile pins its Rust dependency graph. Neither generated
sources nor downloaded binaries are checked in.

## Licensing and limits

RingRTC is AGPL-3.0-only. [LICENSE](LICENSE) is the unchanged upstream notice;
its length is an exception to the repository's 400-line source-file limit.
Generated Cargo lockfiles have the same exception. Dependency adoption must
include the distribution implications of the combined native engine.

See the [probe instructions](../../mosh-probe/media/README.md) for commands and
the distinction between synthetic transport checks and desktop acceptance.
