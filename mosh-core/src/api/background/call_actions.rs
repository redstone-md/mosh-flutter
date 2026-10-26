use super::*;
use crate::api::conversation::BridgeConversationRef;
use flutter_rust_bridge::frb;
use serde::Serialize;
use std::sync::OnceLock;

pub(crate) fn owner_nonce() -> &'static str {
    static NONCE: OnceLock<String> = OnceLock::new();
    NONCE.get_or_init(|| hex::encode(rand::random::<[u8; 32]>()))
}

#[frb(non_opaque)]
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum BackgroundCallActionOutcome {
    Applied,
    Stale,
    Unavailable,
}

#[frb(non_opaque)]
#[derive(Clone, Debug, Serialize)]
pub struct BackgroundCallActionResult {
    pub outcome: BackgroundCallActionOutcome,
    pub action: Option<BackgroundCallAction>,
    pub target: Option<BridgeConversationRef>,
    pub call_id: Option<String>,
}

impl BackgroundCallActionResult {
    pub(crate) fn no(outcome: BackgroundCallActionOutcome) -> Self {
        Self {
            outcome,
            action: None,
            target: None,
            call_id: None,
        }
    }
}

pub(super) fn apply(capability: &str) -> Result<BackgroundCallActionResult, String> {
    let _authority = execution::execution_lease()?;
    crate::api::private_dm::ensure_runtime()
        .map_err(|error| error.to_string())?
        .apply_background_call_action(capability)
}
