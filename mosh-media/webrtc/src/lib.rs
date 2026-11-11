//! The call engine on Google's libwebrtc through LiveKit's bindings: every
//! packet crosses Moss through the virtual network, media is DTLS-SRTP with
//! the fingerprint inside the MLS-authenticated description (ADR 0051).
//! mosh-core loads it through the `mosh_media_*` C ABI.
mod abi;
#[cfg(target_os = "android")]
mod android;
mod audio;
mod carrier;
mod engine;
mod frames;
mod preview;
mod stats;
mod video;
