# Native call media notices

The desktop application bundles mosh-native-media and mosh-camera-capture.
Their source, build scripts, source patches and exact Cargo lockfiles are in
https://github.com/redstone-md/mosh-flutter/tree/main/mosh-media (use the tag or
commit matching the binary). Existing Mosh code retains the root GPL-3.0 license.

mosh-native-media uses Signal RingRTC 2.72.1 and its pinned Signal components,
under AGPL-3.0. The combined desktop distribution must satisfy those terms;
process/library separation is an ownership boundary, not a license exemption.
The bundled AGPL-3.0.txt contains RingRTC's license. RingRTC's prebuilt WebRTC
artifact includes upstream WebRTC/Chromium components; their source and notices
are available through RingRTC's pinned source/build definitions. All Rust
transitive versions and source revisions are recorded in engine/Cargo.lock.

mosh-camera-capture uses nokhwa 0.10.11 and nokhwa-bindings-macos 0.2.4 under
Apache-2.0. Their complete patches and verified archive/source digests are in
third_party/nokhwa-patches and third_party/nokhwa-macos-patches. Their upstream
copyright and license headers are retained. The bundled Apache-2.0.txt contains
the upstream license; capture/Cargo.lock records the remaining Rust components.

X25519, HKDF, SHA-256 and zeroization use the x25519-dalek, hkdf, sha2 and
zeroize crates at the locked revisions. Their license declarations and upstream
source links are retained in their Cargo manifests and the engine lockfile.

These files accompany the libraries/helper in desktop packages. Corresponding
source includes the complete application and native libraries, pinned upstream
sources and patches, and the scripts needed to reproduce the binary.
