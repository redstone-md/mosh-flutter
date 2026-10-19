//! Durable PLUS state. Blinding secrets stay native; wallet keys stay in the wallet.
pub use crate::plus::{PlusOrder, PlusPaymentStatus, PlusPeerBadge, PlusSeries, PlusSnapshot};
use crate::{conversation::now_ms, plus::global};

fn with_owner<T>(
    action: impl FnOnce(&mut crate::plus::PlusRuntime) -> Result<T, String>,
) -> Result<T, String> {
    super::device_link::with_runtime(|runtime| {
        let account = runtime.snapshot()?.user_id;
        Ok::<_, super::device_link::DeviceLinkError>(global::with_owner(&account, action))
    })
    .map_err(|_| "PLUS account unavailable")?
}

pub fn configure_issuer(public_key_b64: String) -> Result<PlusSnapshot, String> {
    let identity = super::device_link::snapshot().map_err(|_| "PLUS account unavailable")?;
    let resources = super::shared_runtime::ensure_shared_resources()?;
    let store = resources
        .persistence
        .ok_or("PLUS requires encrypted storage")?;
    global::configure(store, identity.user_id, &public_key_b64)
}

pub fn snapshot() -> Result<PlusSnapshot, String> {
    with_owner(|owner| Ok(owner.snapshot(now_ms())))
}

pub fn configure_mainnet_issuer(public_key_b64: String) -> Result<PlusSnapshot, String> {
    let identity = super::device_link::snapshot().map_err(|_| "PLUS account unavailable")?;
    let resources = super::shared_runtime::ensure_shared_resources()?;
    let store = resources
        .persistence
        .ok_or("PLUS requires encrypted storage")?;
    global::configure_mode(
        store,
        identity.user_id,
        &public_key_b64,
        Some(&identity.own_device_id),
    )
}

pub fn prepare_series() -> Result<PlusSeries, String> {
    with_owner(|owner| owner.prepare_series())
}

pub fn confirm_series_registered(id: String) -> Result<PlusSnapshot, String> {
    with_owner(|owner| {
        owner.confirm_series_registered(&id)?;
        Ok(owner.snapshot(now_ms()))
    })
}

pub fn prepare_order_issuance(order_id: String) -> Result<String, String> {
    with_owner(|owner| owner.prepare_order_issuance(&order_id))
}

pub fn complete_order_issuance(
    order_id: String,
    blind_signature_b64: String,
) -> Result<PlusSnapshot, String> {
    with_owner(|owner| {
        owner.complete_order_issuance(&order_id, &blind_signature_b64, now_ms())?;
        Ok(owner.snapshot(now_ms()))
    })
}

pub fn save_order(order_json: String) -> Result<PlusSnapshot, String> {
    with_owner(|owner| {
        owner.save_order(&order_json, now_ms())?;
        Ok(owner.snapshot(now_ms()))
    })
}

pub fn prepare_issuance() -> Result<String, String> {
    with_owner(|owner| owner.prepare_issuance())
}

pub fn complete_issuance(blind_signature_b64: String) -> Result<PlusSnapshot, String> {
    with_owner(|owner| {
        owner.complete_issuance(&blind_signature_b64, now_ms())?;
        Ok(owner.snapshot(now_ms()))
    })
}

pub fn set_visible(visible: bool) -> Result<PlusSnapshot, String> {
    with_owner(|owner| {
        owner.set_visible(visible)?;
        Ok(owner.snapshot(now_ms()))
    })
}

#[cfg(test)]
#[path = "plus_tests.rs"]
mod tests;
