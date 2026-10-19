use super::{PlusOrder, PlusRecoveryIssuance, PlusRecoverySession, PlusRuntime};
use base64::{
    engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD},
    Engine,
};
use ed25519_dalek::{Signer, SigningKey};
use rand::RngCore;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeSet;

#[derive(Clone, Serialize, Deserialize)]
pub(super) struct RecoveryState {
    seed: [u8; 32],
    id: String,
    poll_token: String,
    expires_at_ms: u64,
    url: Option<String>,
    orders: BTreeSet<String>,
}

#[derive(Deserialize)]
struct Status {
    id: String,
    code: String,
    expires_at_ms: u64,
    url: String,
    #[serde(default)]
    orders: Vec<PlusOrder>,
}

impl PlusRuntime {
    pub fn prepare_recovery(&mut self, now: u64) -> Result<PlusRecoverySession, String> {
        if !self.checkout_ready() {
            return Err("PLUS recovery is waiting for account synchronization".into());
        }
        if self
            .state
            .mainnet
            .recovery
            .as_ref()
            .is_some_and(|s| s.expires_at_ms > now)
        {
            return self
                .recovery_snapshot()
                .ok_or("missing PLUS recovery".into());
        }
        let mut random = [0; 88];
        rand::rngs::OsRng.fill_bytes(&mut random);
        let seed = self
            .state
            .mainnet
            .recovery
            .as_ref()
            .map(|s| s.seed)
            .unwrap_or(
                random[..32]
                    .try_into()
                    .map_err(|_| "invalid recovery key")?,
            );
        let recovery = RecoveryState {
            seed,
            id: URL_SAFE_NO_PAD.encode(&random[32..56]),
            poll_token: URL_SAFE_NO_PAD.encode(&random[56..]),
            expires_at_ms: now
                .checked_add(900_000)
                .ok_or("invalid recovery deadline")?,
            url: None,
            orders: BTreeSet::new(),
        };
        let mut next = self.state.clone();
        next.mainnet.recovery = Some(recovery);
        self.save(next)?;
        self.recovery_snapshot()
            .ok_or("missing PLUS recovery".into())
    }

    pub fn save_recovery_status(&mut self, json: &str, now: u64) -> Result<(), String> {
        if json.len() > 65536 {
            return Err("PLUS recovery response exceeds size limit".into());
        }
        let status: Status =
            serde_json::from_str(json).map_err(|_| "invalid PLUS recovery response")?;
        let recovery = self.recovery_snapshot().ok_or("no PLUS recovery session")?;
        let url = url::Url::parse(&status.url).map_err(|_| "invalid PLUS recovery URL")?;
        if status.id != recovery.id
            || status.code != recovery.code
            || status.expires_at_ms <= now
            || status.expires_at_ms > now.saturating_add(86_400_000)
            || status.orders.len() > 32
            || !matches!(url.scheme(), "http" | "https")
            || !url.username().is_empty()
            || url.password().is_some()
            || url.query().is_some()
            || url.fragment().is_some()
            || url.path() != format!("/recover/{}", recovery.id)
        {
            return Err("PLUS recovery session mismatch".into());
        }
        let mut next = self.state.clone();
        for mut order in status.orders {
            order.validate()?;
            if order.network != "solana-mainnet"
                || order.issuer_key_id != self.issuer.mainnet_key_id
                || order.valid_from_ms.is_none()
                || order.expires_at_ms.is_none_or(|end| end <= now)
            {
                return Err("invalid recovered PLUS interval".into());
            }
            order.access_token = None;
            if let Some(old) = next.mainnet.orders.get(&order.id) {
                if !old.same_offer(&order)
                    || old.valid_from_ms != order.valid_from_ms
                    || old.expires_at_ms != order.expires_at_ms
                {
                    return Err("recovered PLUS order changed".into());
                }
                order.access_token = old.access_token.clone();
            }
            next.mainnet
                .order_writers
                .entry(order.id.clone())
                .or_insert_with(|| self.writer.clone());
            next.mainnet
                .recovery
                .as_mut()
                .ok_or("no recovery session")?
                .orders
                .insert(order.id.clone());
            next.mainnet.orders.insert(order.id.clone(), order);
        }
        if next.mainnet.orders.len() > 512 {
            return Err("PLUS order limit reached".into());
        }
        let recovery = next
            .mainnet
            .recovery
            .as_mut()
            .ok_or("no recovery session")?;
        recovery.url = Some(status.url);
        recovery.expires_at_ms = status.expires_at_ms;
        self.save(next)
    }

    pub fn prepare_recovery_issuance(&mut self, id: &str) -> Result<PlusRecoveryIssuance, String> {
        let recovery = self
            .state
            .mainnet
            .recovery
            .as_ref()
            .filter(|s| s.orders.contains(id) && s.url.is_some())
            .ok_or("no authorized PLUS recovery order")?
            .clone();
        let blinded_message_b64 = self.prepare_order_issuance(id)?;
        let message = format!(
            "mosh-plus-recovery-issue-v1\0{}\0{id}\0{blinded_message_b64}",
            recovery.id
        );
        let signature = SigningKey::from_bytes(&recovery.seed).sign(message.as_bytes());
        Ok(PlusRecoveryIssuance {
            blinded_message_b64,
            destination_signature_b64: STANDARD.encode(signature.to_bytes()),
        })
    }

    pub(super) fn recovery_snapshot(&self) -> Option<PlusRecoverySession> {
        self.state.mainnet.recovery.as_ref().map(|state| {
            let public_key_b64 = STANDARD.encode(
                SigningKey::from_bytes(&state.seed)
                    .verifying_key()
                    .to_bytes(),
            );
            let code = hex::encode(Sha256::digest(public_key_b64.as_bytes()))[..8].to_uppercase();
            let orders: Vec<_> = state
                .orders
                .iter()
                .filter(|id| !self.state.mainnet.certificates.contains_key(*id))
                .filter_map(|id| self.state.mainnet.orders.get(id).cloned())
                .collect();
            PlusRecoverySession {
                id: state.id.clone(),
                poll_token: state.poll_token.clone(),
                public_key_b64,
                code,
                expires_at_ms: state.expires_at_ms,
                url: state.url.clone(),
                completed_orders: (state.orders.len() - orders.len()) as u32,
                orders,
            }
        })
    }
}
