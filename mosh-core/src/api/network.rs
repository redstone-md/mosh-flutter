//! Network facade.
//!
//! Surfaces the former `list_network_interfaces` Tauri command: enumerates
//! host network interfaces the runtime can bind to. Plain synchronous
//! return; no streams.
//!
//! TYPES (ADR 0010 — 1:1 mapping, DRY): the return type is the runtime's
//! own, re-exported here via `use crate::network_inventory::{...}`. It is
//! NOT redefined. `Result<Vec<NetworkInterfaceInfo>, String>` matches the
//! Tauri command shape exactly; the underlying `list_interfaces` already
//! returns `Result<Vec<NetworkInterfaceInfo>, String>`, so the body is a
//! direct delegate.

use crate::network_inventory::NetworkInterfaceInfo;

/// Enumerate the host's network interfaces (1:1 port of the
/// `list_network_interfaces` Tauri command). Mirrors the runtime's
/// `network_inventory::list_interfaces` name so the api surface matches the
/// runtime method it delegates to.
pub fn list_interfaces() -> Result<Vec<NetworkInterfaceInfo>, String> {
    crate::network_inventory::list_interfaces()
}
