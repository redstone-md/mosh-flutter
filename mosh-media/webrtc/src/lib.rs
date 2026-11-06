//! The call engine on Google's libwebrtc through LiveKit's bindings: every
//! packet crosses Moss through the virtual network, media is DTLS-SRTP with
//! the fingerprint inside the MLS-authenticated description (ADR 0051).
//! Exports the same C ABI as the RingRTC engine.
mod abi;
#[cfg(target_os = "android")]
mod android;
mod audio;
mod camera;
mod carrier;
mod engine;
mod frames;
mod stats;
mod video;
