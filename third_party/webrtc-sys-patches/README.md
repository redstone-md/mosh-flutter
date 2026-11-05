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
Such factories offer only AEAD SRTP profiles. libwebrtc itself is not patched.

Linux builds need clang 21 or later for libwebrtc's hermetic libc++. The probe
README explains how to point `CC`/`CXX` at one.
