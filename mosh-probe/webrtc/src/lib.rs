//! MOSH-60 feasibility engine: Google's libwebrtc through LiveKit's
//! bindings, every packet carried by the embedder over Moss. Exports the
//! same C ABI as mosh-media/engine. Voice only.
mod abi;
mod engine;
mod packets;
mod stats;
