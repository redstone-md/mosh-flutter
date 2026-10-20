use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[frb(non_opaque)]
pub enum PlusPaymentStatus {
    AwaitingPayment,
    Paid,
    Issued,
}

#[derive(Clone, Serialize, Deserialize)]
#[frb(non_opaque)]
pub struct PlusOrder {
    pub id: String,
    pub network: String,
    pub product: String,
    pub mint: String,
    pub recipient: String,
    pub amount_atomic: String,
    pub reference: String,
    pub status: PlusPaymentStatus,
    pub payment_uri: String,
    pub access_token: Option<String>,
    pub transaction_signature: Option<String>,
    pub expires_at_ms: Option<u64>,
    pub blind_signature_b64: Option<String>,
    pub asset: Option<String>,
    pub token_decimals: Option<u8>,
    pub issuer_key_id: Option<String>,
    pub series_id: Option<String>,
    pub valid_from_ms: Option<u64>,
    pub request_id: Option<String>,
}

#[derive(Clone, Serialize)]
#[frb(non_opaque)]
pub struct PlusSnapshot {
    pub active: bool,
    pub visible: bool,
    pub expires_at_ms: Option<u64>,
    pub order: Option<PlusOrder>,
    pub peer_badges: Vec<PlusPeerBadge>,
    #[frb(default = "const []")]
    pub orders: Vec<PlusOrder>,
    pub series: Option<PlusSeries>,
    #[frb(default = false)]
    pub checkout_ready: bool,
    pub next_active_from_ms: Option<u64>,
    #[frb(default = false)]
    pub can_initialize_series: bool,
    #[frb(default = false)]
    pub series_registered: bool,
    pub checkout_intent: Option<super::checkout::PlusCheckoutIntent>,
    pub reserved_until_ms: Option<u64>,
    pub recovery: Option<super::recovery_types::PlusRecoverySession>,
    #[frb(default = "const []")]
    pub unissued_order_ids: Vec<String>,
    #[frb(default = "const []")]
    pub issuable_order_ids: Vec<String>,
}

#[derive(Clone, Serialize, Deserialize, PartialEq, Eq)]
#[frb(non_opaque)]
pub struct PlusSeries {
    pub id: String,
    pub access_token: String,
}

#[derive(Clone, Serialize)]
#[frb(non_opaque)]
pub struct PlusPeerBadge {
    pub identity: String,
    pub expires_at_ms: u64,
}

impl PlusOrder {
    pub(super) fn validate(&self) -> Result<(), String> {
        let amount = self
            .amount_atomic
            .parse::<u64>()
            .map_err(|_| "invalid PLUS price")?;
        if self.id.is_empty()
            || self.id.len() > 128
            || amount == 0
            || amount.to_string() != self.amount_atomic
            || !self.valid_product()
        {
            return Err("invalid PLUS order".into());
        }
        let uri = url::Url::parse(&self.payment_uri).map_err(|_| "invalid PLUS payment URI")?;
        let decimals = self.token_decimals.unwrap_or(9);
        let units = 10_u64.pow(u32::from(decimals));
        let fraction = format!("{:0width$}", amount % units, width = usize::from(decimals));
        let fraction = fraction.trim_end_matches('0');
        let decimal = format!(
            "{}{}{}",
            amount / units,
            if fraction.is_empty() { "" } else { "." },
            fraction
        );
        let params: Vec<_> = uri.query_pairs().collect();
        if uri.scheme() != "solana" || uri.path() != self.recipient || uri.fragment().is_some() {
            return Err("PLUS payment URI recipient mismatch".into());
        }
        for (key, expected) in [
            ("amount", decimal.as_str()),
            ("spl-token", self.mint.as_str()),
            ("reference", self.reference.as_str()),
        ] {
            let values: Vec<_> = params.iter().filter(|(k, _)| k == key).collect();
            if values.len() != 1 || values[0].1 != expected {
                return Err("PLUS payment URI fields mismatch".into());
            }
        }
        Ok(())
    }

    pub(super) fn same_offer(&self, other: &Self) -> bool {
        self.id == other.id
            && self.mint == other.mint
            && self.recipient == other.recipient
            && self.amount_atomic == other.amount_atomic
            && self.reference == other.reference
            && self.payment_uri == other.payment_uri
            && self.network == other.network
            && self.product == other.product
            && self.asset == other.asset
            && self.token_decimals == other.token_decimals
            && self.issuer_key_id == other.issuer_key_id
            && self.series_id == other.series_id
            && self.request_id == other.request_id
    }

    fn valid_product(&self) -> bool {
        match (self.network.as_str(), self.product.as_str()) {
            ("solana-devnet", "mosh-plus-30d") => self.token_decimals.is_none_or(|d| d == 9),
            ("solana-mainnet", "mosh-plus-supporter-30d") => matches!(
                (
                    self.asset.as_deref(),
                    self.mint.as_str(),
                    self.token_decimals
                ),
                (
                    Some("USDC"),
                    "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
                    Some(6)
                ) | (
                    Some("CLXAI"),
                    "ECZV4aRyQKz2zr3ZFB9qeb4EzJbzuMCQZ2gpiBQfoHrK",
                    Some(9)
                )
            ),
            _ => false,
        }
    }
}
