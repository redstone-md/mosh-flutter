//! VPN facade.
//!
//! Surfaces the former VPN-related Tauri command group: `detect_vpn`,
//! `get_bind_interface`, and the `get_vpn_bypass_consent` /
//! `set_vpn_bypass_consent` consent pair. Plain synchronous returns; no
//! streams.
//!
//! Stub: signatures laid for the slice-one boundary; bodies `todo!()` —
//! implemented in a later slice (S2: bound through the bridge). No
//! `OnceLock` / `ensure_runtime` here yet — these stubs compile only and
//! carry no runtime behavior, so the bridge can be generated against the
//! VPN command surface before the wiring lands.
//!
//! TYPES (ADR 0010 — 1:1 mapping, DRY): the consent type is the runtime's
//! own, re-exported here via `use crate::vpn_consent::{...}`. `VpnDetection`
//! was defined inline in the former Tauri shell (`src-tauri/src/lib.rs`),
//! not in mosh-core, so the api facade owns it here as a bridge-friendly
//! struct — the same ownership posture `api::diagnostics` takes for
//! `AppDiagnostics` / `NativeRuntimeStatus`. It is NOT redefined elsewhere.
//! `Result<T, String>` matches the Tauri command shape exactly.

use crate::vpn_consent::VpnBypassConsent;

/// VPN-detection result. Verbatim port of the struct the former Tauri shell
/// defined inline for the `detect_vpn` command, owned here so the bridge
/// serializes it without touching a Tauri-typed type.
#[derive(serde::Serialize, Clone)]
pub struct VpnDetection {
    pub vpn_likely: bool,
    pub suspect_interfaces: Vec<String>,
    /// True when the IPv4 default route currently points through a
    /// virtual / tunnel interface — the strongest signal that an active
    /// VPN owns the user's outbound traffic right now.
    pub vpn_owns_default_route: bool,
}

/// Detect whether a VPN appears to own the default route (1:1 port of the
/// `detect_vpn` Tauri command).
pub fn detect_vpn() -> Result<VpnDetection, String> {
    todo!("slice-2: implement detect_vpn")
}

/// Report the interface the live Moss node is currently bound to (1:1 port
/// of `get_bind_interface`). `None` before any node has started; matches the
/// Tauri command's `Option<String>` return shape directly (no Result wrap —
/// the Tauri command returned `Option<String>`, not `Result`).
pub fn get_bind_interface() -> Option<String> {
    todo!("slice-2: implement get_bind_interface")
}

/// Read the stored VPN-bypass consent (1:1 port of
/// `get_vpn_bypass_consent`). `None` means no prior answer; the bridge asks
/// again next launch. Matches the Tauri command's
/// `Option<VpnBypassConsent>` return shape directly (no Result wrap).
pub fn get_vpn_bypass_consent() -> Option<VpnBypassConsent> {
    todo!("slice-2: implement get_vpn_bypass_consent")
}

/// Record the VPN-bypass consent (1:1 port of `set_vpn_bypass_consent`).
/// `Some(name)` is a yes (remembered); `None` is a refusal (deliberately not
/// stored, so the question returns next launch). The future impl validates
/// the interface against `network_inventory::list_interfaces` before
/// saving, exactly as the Tauri command did.
pub fn set_vpn_bypass_consent(interface: Option<String>) -> Result<(), String> {
    todo!("slice-2: implement set_vpn_bypass_consent")
}
