//! Resumable initial semantic history between admitted devices of one user.
mod fragments;
mod import;
#[cfg(test)]
mod packet_tests;
mod records;
mod source;
mod types;

use super::{invalid, types::Result};
use crate::device_link::{identity::DeviceIdentity, roster::DeviceRoster, types::DeviceDescriptor};
use crate::private_dm_runtime::{contracts::DmHistorySyncState, PrivateDmSession};
pub(super) use types::{HistoryBatch, HistoryExport, HistoryImport, HistoryRequest};

const BATCH_RECORDS: usize = 16;
const SOURCE_TIMEOUT_MS: u64 = 10_000;

impl PrivateDmSession {
    fn authorize_history_device(
        &self,
        identity: &DeviceIdentity,
        sender: &DeviceDescriptor,
        roster: &DeviceRoster,
    ) -> Result<()> {
        let membership = self.membership.as_ref().ok_or_else(invalid)?;
        membership
            .topology
            .validate(&self.session_id, &self.crypto.member_signers())?;
        if membership.joining.is_some()
            || !self.peer_joined
            || roster.digest().map_err(|_| invalid())?
                != identity.roster().digest().map_err(|_| invalid())?
            || roster.user_id() != membership.topology.own_user_id
            || sender.device_id == identity.device().device_id
            || !membership.topology.clients.iter().any(|client| {
                client.device_id == sender.device_id
                    && membership.topology.own(&client.mls_signer)
                    && client.device().is_ok_and(|device| device == *sender)
            })
        {
            return Err(invalid());
        }
        Ok(())
    }

    pub(in crate::private_dm_runtime) fn history_sync_state(
        &self,
        now: u64,
    ) -> Option<DmHistorySyncState> {
        if let Some(state) = self.recovery_sync_state(now) {
            return Some(state);
        }
        let import = self.membership.as_ref()?.history_import.as_ref()?;
        Some(if import.complete {
            DmHistorySyncState::Complete
        } else if self.history_last_rx_ms > 0
            && now.saturating_sub(self.history_last_rx_ms) < SOURCE_TIMEOUT_MS
        {
            DmHistorySyncState::Importing
        } else {
            DmHistorySyncState::WaitingForSource
        })
    }

    pub(in crate::private_dm_runtime::devices) fn history_request(
        &self,
    ) -> Option<(String, super::types::DeviceMessage)> {
        let membership = self.membership.as_ref()?;
        let import = membership.history_import.as_ref()?;
        if import.complete {
            return None;
        }
        let source = membership
            .topology
            .clients
            .iter()
            .find(|client| client.device_id == import.source_device_id)?
            .device()
            .ok()?;
        Some((
            source.moss_peer_id,
            super::types::DeviceMessage::HistoryRequest(HistoryRequest {
                session_id: self.session_id.clone(),
                request_id: import.request_id.clone(),
                offset: import.cursor,
                body_offset: import
                    .partial
                    .as_ref()
                    .map_or(0, |partial| partial.record.body.len()),
            }),
        ))
    }
}
