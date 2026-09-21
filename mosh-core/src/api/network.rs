//! Network facade.
//!
//! Surfaces `list_network_interfaces`: enumerates
//! host network interfaces the runtime can bind to. Plain synchronous
//! return; no streams.
//!
//! TYPES (ADR 0010 — 1:1 mapping, DRY): the return type is the runtime's
//! own, re-exported here via `use crate::network_inventory::{...}`. It is
//! NOT redefined. `Result<Vec<NetworkInterfaceInfo>, String>` matches the
//! underlying `list_interfaces` shape exactly, so the body is a
//! direct delegate.

use crate::network_inventory::NetworkInterfaceInfo;

/// Enumerate the host's network interfaces. Mirrors the runtime's
/// `network_inventory::list_interfaces` name so the api surface matches the
/// runtime method it delegates to.
pub fn list_interfaces() -> Result<Vec<NetworkInterfaceInfo>, String> {
    crate::network_inventory::list_interfaces()
}
