use super::{issuance::PreparedIssuance, Certificate, PlusOrder, PlusRuntime, PlusSeries};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

#[derive(Clone, Serialize, Deserialize)]
struct Item {
    order: PlusOrder,
    writer: String,
    prepared: Option<PreparedIssuance>,
    certificate: Option<Certificate>,
}

#[derive(Serialize, Deserialize)]
struct Page {
    account: String,
    issuer: String,
    series: Option<PlusSeries>,
    committed: bool,
    counter: u64,
    writer: String,
    visible: bool,
    items: Vec<Item>,
    next: Option<String>,
}

impl PlusRuntime {
    pub fn export_sync(&self, after: Option<&str>) -> Result<Option<String>, String> {
        let Some(issuer) = &self.issuer.mainnet_key_id else {
            return Ok(None);
        };
        let items: Vec<_> = self
            .state
            .mainnet
            .orders
            .iter()
            .filter(|(id, _)| after.is_none_or(|after| id.as_str() > after))
            .take(4)
            .map(|(id, order)| Item {
                order: order.clone(),
                writer: self
                    .state
                    .mainnet
                    .order_writers
                    .get(id)
                    .cloned()
                    .unwrap_or_default(),
                prepared: self.state.mainnet.prepared.get(id).cloned(),
                certificate: self.state.mainnet.certificates.get(id).cloned(),
            })
            .collect();
        let next = (items.len() == 4).then(|| items.last().unwrap().order.id.clone());
        let page = Page {
            account: self.state.account_id.clone(),
            issuer: issuer.clone(),
            series: self
                .state
                .mainnet
                .bootstrap
                .registered
                .then(|| self.state.mainnet.series.clone())
                .flatten(),
            committed: self.state.mainnet.bootstrap.committed,
            counter: self.state.mainnet.visibility_counter,
            writer: self.state.mainnet.visibility_writer.clone(),
            visible: self.state.visible,
            items,
            next,
        };
        let json = serde_json::to_string(&page).map_err(|_| "PLUS sync encoding failed")?;
        if json.len() > 24000 {
            return Err("PLUS sync page exceeds size limit".into());
        }
        Ok(Some(json))
    }

    pub fn sync_digest(&self) -> Result<String, String> {
        let mut hash = Sha256::new();
        let mut after = None;
        while let Some(json) = self.export_sync(after.as_deref())? {
            hash.update(json.as_bytes());
            after = serde_json::from_str::<Page>(&json)
                .map_err(|_| "invalid PLUS sync page")?
                .next;
            if after.is_none() {
                break;
            }
        }
        Ok(hex::encode(hash.finalize()))
    }

    pub fn merge_sync(&mut self, json: &str) -> Result<Option<String>, String> {
        if json.len() > 24000 {
            return Err("PLUS sync page exceeds size limit".into());
        }
        let page: Page = serde_json::from_str(json).map_err(|_| "invalid PLUS sync page")?;
        if page.account != self.state.account_id
            || self.issuer.mainnet_key_id.as_deref() != Some(page.issuer.as_str())
            || page.items.len() > 4
            || page.writer.len() > 128
        {
            return Err("PLUS sync account/issuer mismatch".into());
        }
        let mut next = self.state.clone();
        if let Some(series) = page.series {
            if series.id.is_empty()
                || series.id.len() > 128
                || !(32..=128).contains(&series.access_token.len())
            {
                return Err("invalid PLUS series".into());
            }
            if next
                .mainnet
                .series
                .as_ref()
                .is_some_and(|old| old != &series)
            {
                next.mainnet.bootstrap.conflict = true;
                self.save(next)?;
                return Err("conflicting PLUS renewal series".into());
            }
            next.mainnet.series = Some(series);
            next.mainnet.bootstrap.registered = true;
            next.mainnet.bootstrap.committed |= page.committed;
            next.mainnet
                .bootstrap
                .acknowledgements
                .insert(self.writer.clone());
        } else if page.committed {
            return Err("missing committed PLUS series".into());
        }
        match (page.counter, page.writer.as_str()).cmp(&(
            next.mainnet.visibility_counter,
            next.mainnet.visibility_writer.as_str(),
        )) {
            std::cmp::Ordering::Greater => {
                next.mainnet.visibility_counter = page.counter;
                next.mainnet.visibility_writer = page.writer;
                next.visible = page.visible;
            }
            std::cmp::Ordering::Equal if next.visible != page.visible => {
                return Err("conflicting PLUS visibility".into())
            }
            _ => {}
        }
        next.ever_visible |= page.counter > 0;
        for item in page.items {
            self.merge_sync_item(&mut next.mainnet, item)?;
        }
        if next.mainnet.orders.len() > 512 {
            return Err("PLUS order limit reached".into());
        }
        self.save(next)?;
        Ok(page.next)
    }

    fn merge_sync_item(
        &self,
        state: &mut super::mainnet::MainnetState,
        item: Item,
    ) -> Result<(), String> {
        item.order.validate()?;
        let id = item.order.id.clone();
        if item.writer.is_empty()
            || item.writer.len() > 128
            || item.order.issuer_key_id != self.issuer.mainnet_key_id
            || item.order.network != "solana-mainnet"
        {
            return Err("invalid synchronized PLUS order".into());
        }
        if let Some(old) = state.orders.get(&id) {
            if !old.same_offer(&item.order) {
                return Err("conflicting PLUS order".into());
            }
            if old.status > item.order.status {
                return Ok(());
            }
        }
        if let Some(certificate) = item.certificate {
            self.issuer
                .verify_claims(&certificate, &self.state.account_id)?;
            state.certificates.insert(id.clone(), certificate);
        }
        if let Some(prepared) = item.prepared {
            if !prepared.matches(
                &self.state.account_id,
                item.order.valid_from_ms,
                item.order.expires_at_ms,
            ) {
                return Err("invalid PLUS issuance state".into());
            }
            state.prepared.insert(id.clone(), prepared);
        }
        state.order_writers.entry(id.clone()).or_insert(item.writer);
        state.orders.insert(id, item.order);
        Ok(())
    }
}
