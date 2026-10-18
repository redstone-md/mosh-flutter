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
}

#[derive(Clone, Serialize)]
#[frb(non_opaque)]
pub struct PlusSnapshot {
    pub active: bool,
    pub visible: bool,
    pub expires_at_ms: Option<u64>,
    pub order: Option<PlusOrder>,
    pub peer_badges: Vec<PlusPeerBadge>,
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
            || self.network != "solana-devnet"
            || self.product != "mosh-plus-30d"
        {
            return Err("invalid PLUS order".into());
        }
        let uri = url::Url::parse(&self.payment_uri).map_err(|_| "invalid PLUS payment URI")?;
        let fraction = format!("{:09}", amount % 1_000_000_000);
        let fraction = fraction.trim_end_matches('0');
        let decimal = format!(
            "{}{}{}",
            amount / 1_000_000_000,
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
    }
}
