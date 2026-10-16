use super::{
    issuance::PreparedIssuance, Certificate, Issuer, PlusOrder, PlusPaymentStatus, PlusSnapshot,
};
use crate::persistence::Persistence;
use serde::{Deserialize, Serialize};
use std::sync::Arc;

#[derive(Clone, Default, Serialize, Deserialize)]
pub(super) struct LocalState {
    pub account_id: String,
    pub visible: bool,
    order: Option<PlusOrder>,
    prepared: Option<PreparedIssuance>,
    pub certificate: Option<Certificate>,
    #[serde(default)]
    pub revision: u64,
    #[serde(default)]
    pub ever_visible: bool,
    #[serde(default)]
    pub peers: std::collections::BTreeMap<String, super::peers::PeerEvidence>,
}

pub struct PlusRuntime {
    pub(super) store: Arc<Persistence>,
    pub(super) issuer: Issuer,
    pub(super) state: LocalState,
}

impl PlusRuntime {
    pub fn open(
        store: Arc<Persistence>,
        account_id: String,
        issuer_key_b64: &str,
    ) -> Result<Self, String> {
        super::certificate::subject_message(&account_id)?;
        let mut state = match store
            .get_plus_record("local-v1")
            .map_err(|e| e.to_string())?
        {
            Some(bytes) => serde_json::from_slice::<LocalState>(&bytes)
                .map_err(|_| "invalid saved PLUS purchase")?,
            None => LocalState {
                account_id: account_id.clone(),
                ..Default::default()
            },
        };
        if state.account_id != account_id {
            return Err("PLUS purchase belongs to a different account".into());
        }
        let issuer = Issuer::new(issuer_key_b64)?;
        state
            .peers
            .retain(|account, proof| proof.trusted_by(&issuer, account));
        Ok(Self {
            store,
            issuer,
            state,
        })
    }

    pub fn save_order(&mut self, json: &str, now_ms: u64) -> Result<(), String> {
        if json.len() > 16_384 {
            return Err("PLUS order exceeds size limit".into());
        }
        let mut order: PlusOrder = serde_json::from_str(json).map_err(|_| "invalid PLUS order")?;
        order.validate()?;
        if let Some(old) = self.state.order.as_ref().filter(|old| old.id == order.id) {
            if !old.same_offer(&order)
                || order.status < old.status
                || old
                    .expires_at_ms
                    .is_some_and(|expiry| Some(expiry) != order.expires_at_ms)
            {
                return Err("PLUS order changed after acceptance".into());
            }
            order.access_token = old.access_token.clone();
        } else if self.snapshot(now_ms).active
            || self.state.order.as_ref().is_some_and(|o| {
                o.status == PlusPaymentStatus::AwaitingPayment
                    || o.expires_at_ms.is_none_or(|expiry| expiry > now_ms)
            })
        {
            return Err("PLUS purchase is already active".into());
        }
        if order
            .access_token
            .as_ref()
            .is_none_or(|token| token.len() < 32 || token.len() > 128)
        {
            return Err("invalid PLUS order capability".into());
        }
        let mut next = self.state.clone();
        if next.order.as_ref().is_none_or(|old| old.id != order.id) {
            next.prepared = None;
            next.certificate = None;
        }
        next.order = Some(order);
        self.save(next)
    }

    pub fn prepare_issuance(&mut self) -> Result<String, String> {
        if let Some(prepared) = &self.state.prepared {
            return Ok(prepared.blinded_message_b64.clone());
        }
        let order = self.state.order.as_ref().ok_or("no PLUS order")?;
        if order.status != PlusPaymentStatus::Paid {
            return Err("PLUS payment is not ready for issuance".into());
        }
        let prepared = self.issuer.prepare(
            &self.state.account_id,
            order.expires_at_ms.ok_or("missing PLUS expiry")?,
        )?;
        let request = prepared.blinded_message_b64.clone();
        let mut next = self.state.clone();
        next.prepared = Some(prepared);
        self.save(next)?;
        Ok(request)
    }

    pub fn complete_issuance(&mut self, reply: &str, now_ms: u64) -> Result<(), String> {
        let prepared = self
            .state
            .prepared
            .as_ref()
            .ok_or("no pending PLUS issuance")?;
        let certificate = self.issuer.finalize(prepared, reply, now_ms)?;
        let mut next = self.state.clone();
        if next.certificate.as_ref() != Some(&certificate) {
            next.revision = next
                .revision
                .checked_add(1)
                .ok_or("PLUS revision exhausted")?;
        }
        next.certificate = Some(certificate);
        if let Some(order) = next.order.as_mut() {
            order.status = PlusPaymentStatus::Issued;
        }
        self.save(next)
    }

    pub fn set_visible(&mut self, visible: bool) -> Result<(), String> {
        let mut next = self.state.clone();
        if next.visible != visible {
            next.revision = next
                .revision
                .checked_add(1)
                .ok_or("PLUS revision exhausted")?;
        }
        next.ever_visible |= visible;
        next.visible = visible;
        self.save(next)
    }

    pub fn snapshot(&self, now_ms: u64) -> PlusSnapshot {
        let active = self.state.certificate.as_ref().is_some_and(|c| {
            self.issuer
                .verify(c, &self.state.account_id, now_ms)
                .is_ok()
        });
        PlusSnapshot {
            active,
            visible: self.state.visible,
            expires_at_ms: self.state.certificate.as_ref().map(|c| c.expires_at_ms),
            order: self.state.order.clone(),
            peer_badges: self.peer_badges(now_ms),
        }
    }

    pub(super) fn save(&mut self, next: LocalState) -> Result<(), String> {
        let bytes = serde_json::to_vec(&next).map_err(|_| "PLUS purchase encoding failed")?;
        self.store
            .put_plus_record("local-v1", &bytes)
            .map_err(|e| e.to_string())?;
        self.state = next;
        Ok(())
    }
}
