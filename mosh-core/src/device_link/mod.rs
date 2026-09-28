//! Device identity, signed membership and private desktop linking, ADR 0029.
pub mod identity;
mod qr;
pub mod roster;
mod runtime;
pub mod transport;
pub mod types;
pub mod wire;
pub use runtime::DeviceLinkRuntime;
#[cfg(test)]
mod protocol_tests;
