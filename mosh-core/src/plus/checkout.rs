use super::PlusRuntime;
use flutter_rust_bridge::frb;
use rand::RngCore;
use serde::{Deserialize, Serialize};

#[derive(Clone, Serialize, Deserialize)]
#[frb(non_opaque)]
pub struct PlusCheckoutIntent {
    pub request_id: String,
    pub asset: String,
}

impl PlusRuntime {
    /// Cancels an intent before any accepted QR; paid/order records are retained.
    pub fn cancel_checkout(&mut self) -> Result<(), String> {
        if self.issuer.mainnet_key_id.is_none() {
            return Err("not a production PLUS account".into());
        }
        let mut next = self.state.clone();
        next.mainnet.checkout_intent = None;
        self.save(next)
    }

    pub fn prepare_checkout(&mut self, asset: &str) -> Result<PlusCheckoutIntent, String> {
        if !self.checkout_ready() || !matches!(asset, "USDC" | "CLXAI") {
            return Err("PLUS checkout is not ready".into());
        }
        if let Some(intent) = &self.state.mainnet.checkout_intent {
            if intent.asset != asset {
                return Err("PLUS checkout is already pending".into());
            }
            return Ok(intent.clone());
        }
        let mut random = [0; 24];
        rand::rngs::OsRng.fill_bytes(&mut random);
        let intent = PlusCheckoutIntent {
            request_id: hex::encode(random),
            asset: asset.into(),
        };
        let mut next = self.state.clone();
        next.mainnet.checkout_intent = Some(intent.clone());
        self.save(next)?;
        Ok(intent)
    }

    pub fn save_schedule(&mut self, id: &str, reserved_until_ms: u64) -> Result<(), String> {
        if self
            .state
            .mainnet
            .series
            .as_ref()
            .is_none_or(|s| s.id != id)
            || !reserved_until_ms.is_multiple_of(86_400_000)
        {
            return Err("invalid PLUS renewal schedule".into());
        }
        let mut next = self.state.clone();
        next.mainnet.reserved_until_ms = Some(
            next.mainnet
                .reserved_until_ms
                .unwrap_or(0)
                .max(reserved_until_ms),
        );
        self.save(next)
    }
}
