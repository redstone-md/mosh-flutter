//! Durable PLUS state. Blinding secrets stay native; wallet keys stay in the wallet.
pub use crate::plus::{PlusOrder, PlusPaymentStatus, PlusPeerBadge, PlusSnapshot};
use crate::{conversation::now_ms, plus::global};

pub fn configure_issuer(public_key_b64: String) -> Result<PlusSnapshot, String> {
    let identity = super::device_link::snapshot().map_err(|_| "PLUS account unavailable")?;
    let resources = super::shared_runtime::ensure_shared_resources()?;
    let store = resources
        .persistence
        .ok_or("PLUS requires encrypted storage")?;
    global::configure(store, identity.user_id, &public_key_b64)
}

pub fn snapshot() -> Result<PlusSnapshot, String> {
    global::with_owner(|owner| Ok(owner.snapshot(now_ms())))
}

pub fn save_order(order_json: String) -> Result<PlusSnapshot, String> {
    global::with_owner(|owner| {
        owner.save_order(&order_json, now_ms())?;
        Ok(owner.snapshot(now_ms()))
    })
}

pub fn prepare_issuance() -> Result<String, String> {
    global::with_owner(|owner| owner.prepare_issuance())
}

pub fn complete_issuance(blind_signature_b64: String) -> Result<PlusSnapshot, String> {
    global::with_owner(|owner| {
        owner.complete_issuance(&blind_signature_b64, now_ms())?;
        Ok(owner.snapshot(now_ms()))
    })
}

pub fn set_visible(visible: bool) -> Result<PlusSnapshot, String> {
    global::with_owner(|owner| {
        owner.set_visible(visible)?;
        Ok(owner.snapshot(now_ms()))
    })
}
