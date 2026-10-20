use super::{PlusRuntime, PlusSeries};
use rand::RngCore;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeSet;

#[derive(Clone, Default, Serialize, Deserialize)]
pub(super) struct Bootstrap {
    pub roster: String,
    pub initializer: String,
    pub members: Vec<String>,
    pub registered: bool,
    pub committed: bool,
    pub conflict: bool,
    pub acknowledgements: BTreeSet<String>,
}

impl PlusRuntime {
    /// Caller supplies the verified current device roster, never UI input.
    pub fn reconcile_plus_roster(
        &mut self,
        roster: &str,
        initializer: &str,
        members: &[String],
    ) -> Result<(), String> {
        if self.issuer.mainnet_key_id.is_none() {
            return Ok(());
        }
        if members.len() > 64 || roster.is_empty() || initializer.is_empty() {
            return Err("invalid PLUS device roster".into());
        }
        let mut next = self.state.clone();
        let bootstrap = &mut next.mainnet.bootstrap;
        if bootstrap.roster == roster
            && bootstrap.initializer == initializer
            && bootstrap.members == members
        {
            return Ok(());
        }
        if bootstrap.roster != roster {
            bootstrap.acknowledgements.clear();
        }
        bootstrap.roster = roster.into();
        bootstrap.initializer = initializer.into();
        bootstrap.members = members.to_vec();
        if bootstrap.registered {
            bootstrap.acknowledgements.insert(self.writer.clone());
        }
        bootstrap.commit_if_saved();
        self.save(next)
    }

    pub(super) fn can_initialize_series(&self) -> bool {
        let bootstrap = &self.state.mainnet.bootstrap;
        self.writer == bootstrap.initializer
            && bootstrap.members.contains(&self.writer)
            && !bootstrap.conflict
    }

    pub(super) fn checkout_ready(&self) -> bool {
        let bootstrap = &self.state.mainnet.bootstrap;
        self.state.mainnet.series.is_some()
            && bootstrap.registered
            && bootstrap.committed
            && !bootstrap.conflict
            && bootstrap.members.contains(&self.writer)
    }

    pub fn prepare_series(&mut self) -> Result<PlusSeries, String> {
        if !self.can_initialize_series() {
            return Err("PLUS is waiting for the original device to synchronize".into());
        }
        if let Some(series) = &self.state.mainnet.series {
            return Ok(series.clone());
        }
        let mut random = [0; 56];
        rand::rngs::OsRng.fill_bytes(&mut random);
        self.save_series(&hex::encode(&random[..24]), &hex::encode(&random[24..]))?;
        Ok(self
            .state
            .mainnet
            .series
            .clone()
            .ok_or("missing PLUS series")?)
    }

    pub fn confirm_series_registered(&mut self, id: &str) -> Result<(), String> {
        if !self.can_initialize_series()
            || self
                .state
                .mainnet
                .series
                .as_ref()
                .is_none_or(|s| s.id != id)
        {
            return Err("PLUS series registration mismatch".into());
        }
        let mut next = self.state.clone();
        next.mainnet.bootstrap.registered = true;
        next.mainnet
            .bootstrap
            .acknowledgements
            .insert(self.writer.clone());
        next.mainnet.bootstrap.commit_if_saved();
        self.save(next)
    }

    pub fn series_digest(&self) -> Result<String, String> {
        let bootstrap = &self.state.mainnet.bootstrap;
        let bytes = serde_json::to_vec(&(
            &self.state.mainnet.series,
            bootstrap.registered,
            &bootstrap.roster,
        ))
        .map_err(|_| "PLUS series encoding failed")?;
        Ok(hex::encode(Sha256::digest(bytes)))
    }

    pub fn acknowledge_sync(&mut self, device: &str, series_digest: &str) -> Result<(), String> {
        let bootstrap = &self.state.mainnet.bootstrap;
        if !bootstrap.registered
            || !bootstrap.members.iter().any(|id| id == device)
            || self.series_digest()? != series_digest
            || bootstrap.acknowledgements.contains(device)
        {
            return Ok(());
        }
        let mut next = self.state.clone();
        next.mainnet
            .bootstrap
            .acknowledgements
            .insert(device.into());
        next.mainnet.bootstrap.commit_if_saved();
        self.save(next)
    }
}

impl Bootstrap {
    fn commit_if_saved(&mut self) {
        if self.registered
            && !self.members.is_empty()
            && self
                .members
                .iter()
                .all(|id| self.acknowledgements.contains(id))
        {
            self.committed = true;
        }
    }
}
