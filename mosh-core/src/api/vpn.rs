//! VPN facade.
//!
//! Surfaces the VPN-related command group: `detect_vpn`,
//! `get_bind_interface`, and the `get_vpn_bypass_consent` /
//! `set_vpn_bypass_consent` consent pair. Plain synchronous returns; no
//! streams.
//!
//! TYPES (ADR 0010 — 1:1 mapping, DRY): the consent type is the runtime's
//! own, re-exported here via `use crate::vpn_consent::{...}`. `VpnDetection`
//! has no mosh-core definition, so the api facade owns it here as a
//! bridge-friendly struct — the same ownership posture `api::diagnostics`
//! takes for `AppDiagnostics` / `NativeRuntimeStatus`. It is NOT redefined
//! elsewhere.

use crate::vpn_consent::VpnBypassConsent;

/// VPN-detection result, owned here so the bridge
/// serializes it without touching a runtime-typed type.
#[derive(serde::Serialize, Clone)]
pub struct VpnDetection {
    pub vpn_likely: bool,
    pub suspect_interfaces: Vec<String>,
    /// True when the IPv4 default route currently points through a
    /// virtual / tunnel interface — the strongest signal that an active
    /// VPN owns the user's outbound traffic right now.
    pub vpn_owns_default_route: bool,
}

/// Detect whether a VPN appears to own the default route.
pub fn detect_vpn() -> Result<VpnDetection, String> {
    let interfaces = crate::network_inventory::list_interfaces()?;
    let mut suspect = Vec::new();
    let mut owns_default = false;
    for iface in &interfaces {
        if iface.is_loopback {
            continue;
        }
        if iface.is_vpn {
            suspect.push(iface.name.clone());
            if iface.is_default_route {
                owns_default = true;
            }
        }
    }
    Ok(VpnDetection {
        vpn_likely: !suspect.is_empty(),
        suspect_interfaces: suspect,
        vpn_owns_default_route: owns_default,
    })
}

/// Report the interface the live Moss node is currently bound to.
/// `None` before any node has started.
pub fn get_bind_interface() -> Option<String> {
    crate::moss_ffi::current_bind_interface()
}

/// Read the stored VPN-bypass consent. `None` means no prior answer; the
/// bridge asks again next launch.
pub fn get_vpn_bypass_consent() -> Option<VpnBypassConsent> {
    crate::vpn_consent::load(&crate::api::shared_runtime::resolved_data_dir())
}

/// Record the VPN-bypass consent.
/// `Some(name)` is a yes (remembered); `None` is a refusal (deliberately not
/// stored, so the question returns next launch). Validates the interface
/// against `network_inventory::list_interfaces` before saving.
pub fn set_vpn_bypass_consent(interface: Option<String>) -> Result<(), String> {
    let dir = crate::api::shared_runtime::resolved_data_dir();
    let Some(name) = interface.filter(|name| !name.is_empty()) else {
        return crate::vpn_consent::clear(&dir).map_err(|error| error.to_string());
    };
    let interfaces = crate::network_inventory::list_interfaces()?;
    let iface = interfaces
        .iter()
        .find(|iface| iface.name == name && iface.is_up && !iface.is_loopback && !iface.is_virtual)
        .ok_or_else(|| format!("interface {name:?} is not a usable physical adapter"))?;
    crate::vpn_consent::save(
        &dir,
        &crate::vpn_consent::VpnBypassConsent {
            interface: iface.name.clone(),
            index: iface.index,
        },
    )
    .map_err(|error| error.to_string())
}
