# libwebrtc crate patch

[mosh.patch](mosh.patch) exposes the virtual network from
[webrtc-sys-patches](../webrtc-sys-patches/README.md) in the safe API:
`virtual_network::VirtualNetwork` and
`PeerConnectionFactory::with_virtual_network`.
