# Native call media notices

The desktop application bundles mosh-native-media and mosh-camera-capture.
Android bundles the same engine with the Java API of its libwebrtc build;
Camera2/Camera1 adapters replace the desktop capture helper. Its APK assets
include these notices, the GPL text and libwebrtc's generated dependency
licenses under `native-media/`.
Their source, build scripts, source patches and exact Cargo lockfiles are in
https://github.com/redstone-md/mosh-flutter/tree/main/mosh-media (use the tag or
commit matching the binary). Existing Mosh code retains the root GPL-3.0 license.

mosh-native-media (webrtc/) uses LiveKit's webrtc-sys 0.3.53 and libwebrtc
0.4.0 crates under Apache-2.0, with the complete patches and verified digests
in third_party/webrtc-sys-patches and third_party/libwebrtc-patches, and
statically links Google's libwebrtc (BSD-3-Clause) as built from LiveKit's
webrtc-sdk fork at the commit pinned in third_party/libwebrtc-build, without
H.264. The bundled WEBRTC-LICENSE.md is that build's generated dependency
license list; webrtc/Cargo.lock records the remaining Rust components.

mosh-camera-capture uses nokhwa 0.10.11 and nokhwa-bindings-macos 0.2.4 under
Apache-2.0. Their complete patches and verified archive/source digests are in
third_party/nokhwa-patches and third_party/nokhwa-macos-patches. Their upstream
copyright and license headers are retained. The bundled Apache-2.0.txt contains
the upstream license; capture/Cargo.lock records the remaining Rust components.
Its JPEG decoding uses mozjpeg: this software is based in part on the work of
the Independent JPEG Group.

These files accompany the libraries/helper in desktop packages. Corresponding
source includes the complete application and native libraries, pinned upstream
sources and patches, and the scripts needed to reproduce the binary.
