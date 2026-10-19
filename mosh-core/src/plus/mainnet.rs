use super::{
    issuance::PreparedIssuance, Certificate, Issuer, MainnetClaims, PlusOrder, PlusPaymentStatus,
    PlusRuntime, PlusSeries, PlusSnapshot,
};
use crate::persistence::Persistence;
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, sync::Arc};

#[derive(Clone, Default, Serialize, Deserialize)]
pub(super) struct MainnetState {
    pub series: Option<PlusSeries>,
    pub orders: BTreeMap<String, PlusOrder>,
    pub prepared: BTreeMap<String, PreparedIssuance>,
    pub certificates: BTreeMap<String, Certificate>,
    pub visibility_counter: u64,
    pub visibility_writer: String,
    pub checkout_ready: bool,
    #[serde(default)]
    pub peers: BTreeMap<String, super::mainnet_peers::PeerProof>,
    #[serde(default)]
    pub bootstrap: super::bootstrap::Bootstrap,
    #[serde(default)]
    pub order_writers: BTreeMap<String, String>,
    #[serde(default)]
    pub checkout_intent: Option<super::checkout::PlusCheckoutIntent>,
    #[serde(default)]
    pub reserved_until_ms: Option<u64>,
    #[serde(default)]
    pub recovery: Option<super::recovery::RecoveryState>,
}

impl PlusRuntime {
    pub fn open_mainnet(
        store: Arc<Persistence>,
        account_id: String,
        key: &str,
        writer: &str,
    ) -> Result<Self, String> {
        Self::open_with_issuer(store, account_id, Issuer::mainnet(key)?, writer)
    }

    pub fn save_series(&mut self, id: &str, token: &str) -> Result<(), String> {
        if self.issuer.mainnet_key_id.is_none()
            || id.is_empty()
            || id.len() > 128
            || !(32..=128).contains(&token.len())
        {
            return Err("invalid PLUS renewal series".into());
        }
        let series = PlusSeries {
            id: id.into(),
            access_token: token.into(),
        };
        if self
            .state
            .mainnet
            .series
            .as_ref()
            .is_some_and(|old| old != &series)
        {
            return Err("PLUS renewal series already exists".into());
        }
        let mut next = self.state.clone();
        next.mainnet.series = Some(series);
        self.save(next)
    }

    pub(super) fn save_mainnet_order(&mut self, json: &str) -> Result<(), String> {
        if json.len() > 16_384 {
            return Err("PLUS order exceeds size limit".into());
        }
        let mut order: PlusOrder = serde_json::from_str(json).map_err(|_| "invalid PLUS order")?;
        order.validate()?;
        if order.issuer_key_id != self.issuer.mainnet_key_id
            || order.network != "solana-mainnet"
            || order.series_id.as_deref()
                != self.state.mainnet.series.as_ref().map(|s| s.id.as_str())
        {
            return Err("PLUS order issuer/series mismatch".into());
        }
        if let Some(old) = self.state.mainnet.orders.get(&order.id) {
            if !old.same_offer(&order)
                || order.status < old.status
                || old
                    .expires_at_ms
                    .is_some_and(|until| Some(until) != order.expires_at_ms)
                || old
                    .valid_from_ms
                    .is_some_and(|from| Some(from) != order.valid_from_ms)
            {
                return Err("PLUS order changed after acceptance".into());
            }
            order.access_token = old.access_token.clone();
        } else if self.state.mainnet.orders.len() >= 512 {
            return Err("PLUS order limit reached".into());
        }
        if order
            .access_token
            .as_ref()
            .is_none_or(|t| !(32..=128).contains(&t.len()))
        {
            return Err("invalid PLUS order capability".into());
        }
        let mut next = self.state.clone();
        if !next.mainnet.orders.contains_key(&order.id) {
            if let Some(intent) = &next.mainnet.checkout_intent {
                if order.request_id.as_deref() != Some(&intent.request_id)
                    || order.asset.as_deref() != Some(&intent.asset)
                {
                    return Err("PLUS checkout response mismatch".into());
                }
                next.mainnet.checkout_intent = None;
            }
        }
        next.mainnet
            .order_writers
            .entry(order.id.clone())
            .or_insert_with(|| self.writer.clone());
        next.mainnet.orders.insert(order.id.clone(), order);
        self.save(next)
    }

    pub fn prepare_order_issuance(&mut self, id: &str) -> Result<String, String> {
        if let Some(prepared) = self.state.mainnet.prepared.get(id) {
            return Ok(prepared.blinded_message_b64.clone());
        }
        if self
            .state
            .mainnet
            .order_writers
            .get(id)
            .is_some_and(|writer| writer != &self.writer)
        {
            return Err("PLUS issuance is waiting for its device to synchronize".into());
        }
        let order = self.state.mainnet.orders.get(id).ok_or("no PLUS order")?;
        if order.status == PlusPaymentStatus::AwaitingPayment {
            return Err("PLUS payment is not ready".into());
        }
        let claims = MainnetClaims {
            issuer_key_id: self.issuer.mainnet_key_id.clone().ok_or("not mainnet")?,
            valid_from_ms: order.valid_from_ms.ok_or("missing PLUS start")?,
        };
        let until = order.expires_at_ms.ok_or("missing PLUS expiry")?;
        if claims.valid_from_ms >= until || !claims.valid_from_ms.is_multiple_of(86_400_000) {
            return Err("invalid PLUS interval".into());
        }
        let prepared = self
            .issuer
            .prepare_claims(&self.state.account_id, until, Some(claims))?;
        let blind = prepared.blinded_message_b64.clone();
        let mut next = self.state.clone();
        next.mainnet.prepared.insert(id.into(), prepared);
        self.save(next)?;
        Ok(blind)
    }

    pub fn complete_order_issuance(
        &mut self,
        id: &str,
        reply: &str,
        now: u64,
    ) -> Result<(), String> {
        let prepared = self
            .state
            .mainnet
            .prepared
            .get(id)
            .ok_or("no pending PLUS issuance")?;
        let certificate = self.issuer.finalize(prepared, reply, now)?;
        let mut next = self.state.clone();
        next.mainnet.certificates.insert(id.into(), certificate);
        next.mainnet
            .orders
            .get_mut(id)
            .ok_or("no PLUS order")?
            .status = PlusPaymentStatus::Issued;
        self.save(next)
    }

    pub(super) fn set_mainnet_visible(&mut self, visible: bool) -> Result<(), String> {
        let mut next = self.state.clone();
        if next.visible != visible {
            next.mainnet.visibility_counter = next
                .mainnet
                .visibility_counter
                .checked_add(1)
                .ok_or("PLUS revision exhausted")?;
            next.mainnet.visibility_writer = self.writer.clone();
        }
        next.visible = visible;
        next.ever_visible |= visible;
        self.save(next)
    }

    pub(super) fn mainnet_snapshot(&self, now: u64) -> PlusSnapshot {
        let mut certificates: Vec<_> = self
            .state
            .mainnet
            .certificates
            .values()
            .filter(|c| self.issuer.verify_claims(c, &self.state.account_id).is_ok())
            .collect();
        certificates.sort_by_key(|c| c.mainnet.as_ref().map(|claims| claims.valid_from_ms));
        let active = certificates
            .iter()
            .any(|c| self.issuer.verify(c, &self.state.account_id, now).is_ok());
        let mut until = certificates
            .iter()
            .filter(|c| self.issuer.verify(c, &self.state.account_id, now).is_ok())
            .map(|c| c.expires_at_ms)
            .max();
        for certificate in &certificates {
            if let (Some(end), Some(claims)) = (until, &certificate.mainnet) {
                if claims.valid_from_ms <= end {
                    until = Some(end.max(certificate.expires_at_ms));
                }
            }
        }
        let orders: Vec<_> = self.state.mainnet.orders.values().cloned().collect();
        PlusSnapshot {
            active,
            visible: self.state.visible,
            expires_at_ms: until,
            order: orders
                .iter()
                .find(|o| o.status != PlusPaymentStatus::Issued)
                .cloned(),
            orders,
            peer_badges: self.peer_badges(now),
            series: self.state.mainnet.series.clone(),
            checkout_ready: self.checkout_ready(),
            can_initialize_series: self.can_initialize_series(),
            series_registered: self.state.mainnet.bootstrap.registered,
            checkout_intent: self.state.mainnet.checkout_intent.clone(),
            reserved_until_ms: self.state.mainnet.reserved_until_ms,
            recovery: self.recovery_snapshot(),
            unissued_order_ids: self
                .state
                .mainnet
                .orders
                .keys()
                .filter(|id| !self.state.mainnet.certificates.contains_key(*id))
                .cloned()
                .collect(),
            next_active_from_ms: certificates
                .iter()
                .filter_map(|c| c.mainnet.as_ref().map(|p| p.valid_from_ms))
                .filter(|from| *from > now)
                .min(),
        }
    }
}
