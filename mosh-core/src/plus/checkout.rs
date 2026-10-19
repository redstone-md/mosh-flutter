use super::PlusRuntime;
use flutter_rust_bridge::frb;
use rand::RngCore;
use serde::{Deserialize, Serialize};

#[derive(Clone, Serialize, Deserialize)]
#[frb(non_opaque)]
pub struct PlusCheckoutIntent {
    pub request_id: String,
    pub asset: String,
    #[serde(default)]
    pub offer_json: Option<String>,
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
            offer_json: None,
        };
        let mut next = self.state.clone();
        next.mainnet.checkout_intent = Some(intent.clone());
        self.save(next)?;
        Ok(intent)
    }

    /// Pin accepted catalog terms before the first HTTP request can be lost.
    pub fn bind_checkout_offer(&mut self, json: &str) -> Result<PlusCheckoutIntent, String> {
        if json.len() > 4096 {
            return Err("PLUS checkout terms exceed size limit".into());
        }
        let offer: serde_json::Value =
            serde_json::from_str(json).map_err(|_| "invalid PLUS checkout terms")?;
        let mut next = self.state.clone();
        let intent = next
            .mainnet
            .checkout_intent
            .as_mut()
            .ok_or("no PLUS checkout")?;
        if offer["asset"].as_str() != Some(&intent.asset)
            || offer["issuer_key_id"].as_str() != self.issuer.mainnet_key_id.as_deref()
            || offer["network"] != "solana-mainnet"
            || offer["product"] != "mosh-plus-supporter-30d"
        {
            return Err("PLUS checkout terms mismatch".into());
        }
        if let Some(old) = &intent.offer_json {
            if old != json {
                return Err("PLUS checkout terms already fixed".into());
            }
        }
        intent.offer_json = Some(json.into());
        let intent = intent.clone();
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

impl PlusCheckoutIntent {
    pub(super) fn validate_quote(&self, order: &super::PlusOrder) -> Result<(), String> {
        if let Some(terms) = &self.offer_json {
            let terms: serde_json::Value =
                serde_json::from_str(terms).map_err(|_| "invalid PLUS checkout terms")?;
            let quote = serde_json::to_value(order).map_err(|_| "invalid PLUS quote")?;
            if terms.as_object().is_none_or(|terms| {
                terms
                    .iter()
                    .any(|(key, value)| quote.get(key) != Some(value))
            }) {
                return Err("PLUS checkout quote changed".into());
            }
        }
        Ok(())
    }
}
