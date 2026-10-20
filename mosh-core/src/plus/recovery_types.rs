use super::PlusOrder;
use flutter_rust_bridge::frb;
use serde::Serialize;

#[derive(Clone, Serialize)]
#[frb(non_opaque)]
pub struct PlusRecoverySession {
    pub id: String,
    pub poll_token: String,
    pub public_key_b64: String,
    pub code: String,
    pub expires_at_ms: u64,
    pub url: Option<String>,
    pub orders: Vec<PlusOrder>,
    pub completed_orders: u32,
}

#[derive(Clone, Serialize)]
#[frb(non_opaque)]
pub struct PlusRecoveryIssuance {
    pub blinded_message_b64: String,
    pub destination_signature_b64: String,
}
