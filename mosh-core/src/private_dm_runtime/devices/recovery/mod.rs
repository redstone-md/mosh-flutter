mod epochs;
mod import;
mod relay;
mod source;
mod types;

pub(super) use epochs::{EpochAuthorization, EpochRecord};
pub(super) use types::*;

use super::history::{HistoryExport, HistoryImport, HistoryRequest};
use super::invalid;
use super::types::{DeviceMembership, DeviceMessage, Result};
use crate::device_link::{roster::DeviceRoster, types::DeviceDescriptor};
use crate::persistence::Persistence;
use crate::private_dm_runtime::contracts::DmHistorySyncState;
use crate::private_dm_runtime::{PrivateDmRuntime, PrivateDmSession};
use sha2::{Digest, Sha256};

const PROBE_MS: u64 = 5_000;
const SOURCE_TIMEOUT_MS: u64 = 10_000;

impl DeviceMembership {
    pub(super) fn require_epoch(&mut self, epoch: u64, current: u64) {
        let recovery = self
            .recovery
            .get_or_insert_with(|| Recovery::new(crate::private_dm_runtime::now_ms(), current));
        recovery.required_epoch = recovery.required_epoch.max(epoch);
        if let Some(source) = &mut recovery.source {
            source.epoch = source.epoch.max(epoch);
        }
    }
}

impl PrivateDmSession {
    fn authorize_recovery_device(
        &self,
        sender: &DeviceDescriptor,
        roster: &DeviceRoster,
    ) -> Result<()> {
        let membership = self.membership.as_ref().ok_or_else(invalid)?;
        membership
            .topology
            .validate(&self.session_id, &self.crypto.member_signers())?;
        let client = membership
            .topology
            .clients
            .iter()
            .find(|client| client.device_id == sender.device_id)
            .ok_or_else(invalid)?;
        let current = membership
            .topology
            .roster(&roster.user_id())
            .ok_or_else(invalid)?;
        if membership.joining.is_some()
            || !membership.authorized(sender, &roster.user_id())
            || !self.peer_joined
            || client.mls_signer == hex::encode(self.crypto.signer_public())
            || client.device()? != *sender
            || !current.devices().map_err(|_| invalid())?.contains(sender)
            || !(roster.extends(current).map_err(|_| invalid())?
                || current.extends(roster).map_err(|_| invalid())?)
        {
            return Err(invalid());
        }
        Ok(())
    }

    fn recovery_manifest(&self) -> Result<String> {
        let keys = HistoryExport::keys(self)?;
        let bytes = serde_json::to_vec(&keys).map_err(|_| invalid())?;
        Ok(hex::encode(Sha256::digest(bytes)))
    }

    pub(in crate::private_dm_runtime::devices) fn save_recovery_membership(
        &mut self,
        store: &Persistence,
        next: DeviceMembership,
    ) -> Result<()> {
        let mut record = self.to_persisted_record();
        record.membership = Some(next.clone());
        store.put_session(
            &self.session_id,
            &serde_json::to_vec(&record).map_err(|_| invalid())?,
        )?;
        self.membership = Some(next);
        Ok(())
    }

    pub(in crate::private_dm_runtime) fn recovery_sync_state(
        &self,
        now: u64,
    ) -> Option<DmHistorySyncState> {
        let recovery = self.membership.as_ref()?.recovery.as_ref()?;
        if self
            .crypto
            .epoch()
            .is_some_and(|epoch| epoch < recovery.required_epoch)
        {
            return Some(DmHistorySyncState::WaitingForSource);
        }
        if recovery.source.is_some() {
            return Some(
                if self.history_last_rx_ms > 0
                    && now.saturating_sub(self.history_last_rx_ms) < SOURCE_TIMEOUT_MS
                {
                    DmHistorySyncState::Importing
                } else {
                    DmHistorySyncState::WaitingForSource
                },
            );
        }
        if now.saturating_sub(recovery.last_rx_ms) >= SOURCE_TIMEOUT_MS {
            Some(DmHistorySyncState::WaitingForSource)
        } else {
            (!recovery.observed.is_empty()).then_some(DmHistorySyncState::Complete)
        }
    }

    pub(in crate::private_dm_runtime::devices) fn recovery_packets(
        &mut self,
        store: &Persistence,
        now: u64,
    ) -> Result<Vec<(String, DeviceMessage)>> {
        let mut next = self.membership.clone().ok_or_else(invalid)?;
        if !next.live()
            || next.revoked
            || next.joining.is_some()
            || !self.peer_joined
            || (!self.awaiting_device_epoch()
                && next
                    .history_import
                    .as_ref()
                    .is_some_and(|import| !import.complete))
        {
            return Ok(Vec::new());
        }
        next.topology
            .validate(&self.session_id, &self.crypto.member_signers())?;
        if self.recovery_boot_ms == 0 {
            self.recovery_boot_ms = now;
        }
        let recovery = next
            .recovery
            .get_or_insert_with(|| Recovery::new(now, self.crypto.epoch().unwrap_or(0)));
        if recovery.source.is_some()
            && now.saturating_sub(recovery.last_rx_ms.max(self.recovery_boot_ms))
                < SOURCE_TIMEOUT_MS
        {
            // An answer already sent its follow-up pull; repeat it only after
            // a retry interval without one.
            if now.saturating_sub(self.recovery_pull_ms) < super::RETRY_MS {
                return Ok(Vec::new());
            }
            return self.recovery_pull(recovery).map(|packet| vec![packet]);
        }
        if recovery.source.is_none() && now.saturating_sub(recovery.started_ms) < PROBE_MS {
            return Ok(Vec::new());
        }
        recovery.round = recovery.round.checked_add(1).ok_or_else(invalid)?;
        recovery.request_id = self.crypto.random_token("recovery")?;
        recovery.started_ms = now;
        recovery.source = None;
        let probe = RecoveryProbe {
            session_id: self.session_id.clone(),
            request_id: recovery.request_id.clone(),
            round: recovery.round,
        };
        let packets = self.recovery_probe_packets(probe)?;
        self.save_recovery_membership(store, next)?;
        Ok(packets)
    }

    fn recovery_probe_packets(&self, probe: RecoveryProbe) -> Result<Vec<(String, DeviceMessage)>> {
        self.recovery_candidates()?
            .into_iter()
            .map(|device| {
                Ok((
                    device.moss_peer_id,
                    DeviceMessage::RecoveryProbe(probe.clone()),
                ))
            })
            .collect()
    }

    fn recovery_pull(&self, recovery: &Recovery) -> Result<(String, DeviceMessage)> {
        let source = recovery.source.as_ref().ok_or_else(invalid)?;
        let peer = self
            .recovery_candidates()?
            .into_iter()
            .find(|device| device.device_id == source.device_id)
            .ok_or_else(invalid)?
            .moss_peer_id;
        Ok((
            peer,
            DeviceMessage::RecoveryPull(RecoveryPull {
                round: recovery.round,
                epoch: self.crypto.epoch().ok_or_else(invalid)?,
                request: HistoryRequest {
                    session_id: self.session_id.clone(),
                    request_id: source.import.request_id.clone(),
                    offset: source.import.cursor,
                    body_offset: source
                        .import
                        .partial
                        .as_ref()
                        .map_or(0, |partial| partial.record.body.len()),
                },
            }),
        ))
    }
}
