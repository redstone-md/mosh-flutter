//! Device identity, signed membership and private desktop linking, ADR 0029.
pub mod identity;
mod names_wire;
mod qr;
pub mod roster;
mod runtime;
pub mod transport;
pub mod types;
pub mod wire;
pub use runtime::DeviceLinkRuntime;
#[cfg(test)]
mod identity_tests;
#[cfg(test)]
mod protocol_tests;

#[cfg(test)]
mod names_wire_tests;
