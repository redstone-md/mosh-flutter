# LiveKit libwebrtc bindings with a virtual network

`node scripts/livekit-webrtc-prepare.mjs` reconstructs `webrtc-sys` 0.3.53 and
`libwebrtc` 0.4.0 from crates.io, applies the patches here and in
[libwebrtc-patches](../libwebrtc-patches), and checks the archive and patched
tree hashes in each `source.json`. Both crates are Apache-2.0, like the patches.
They wrap Google's libwebrtc (BSD-3-Clause) as built by LiveKit.

[mosh.patch](mosh.patch) adds `VirtualNetwork`: one IPv4 interface with UDP
sockets whose packets leave through a Rust closure and arrive through
`receive()`. A factory created with it gets libwebrtc's own
`PacketSocketFactory` and `NetworkManager` dependencies, so ICE, DTLS and SRTP
run unchanged while no OS socket, interface enumeration or DNS lookup happens.
Such factories offer only AEAD SRTP profiles. A network serves one factory and
is detached when that factory ends. Google's libwebrtc (the C++ library) is not
patched; only these two binding crates are.

It also changes LiveKit's libwebrtc build scripts in `libwebrtc/`: no H.264
(so no FFmpeg branding either) and a shallow Windows checkout dated by its
own commit, and they run from any work directory. Our builds use them
([libwebrtc-build](../libwebrtc-build/README.md)).

The patch is a generated, reviewed artefact and, like lockfiles and upstream
license texts, is exempt from the 400-line source file limit.

Linux builds need clang 21 or later for libwebrtc's hermetic libc++: point
`CC`/`CXX` at one, for example Chromium's own toolchain (the revision is
`CR_CLANG_REVISION` in the build's `webrtc.ninja`) or an LLVM release.
