use super::{records::TextRecord, types::*, *};
use crate::conversation::history::StoredMessage;
use crate::persistence::Persistence;
use crate::private_dm_runtime::{ChatMessage, PrivateDmRuntime};
use std::collections::HashSet;

impl PrivateDmSession {
    fn import_history_batch(
        &mut self,
        store: &Persistence,
        sender: &DeviceDescriptor,
        roster: &DeviceRoster,
        batch: HistoryBatch,
    ) -> Result<()> {
        let mut membership = self.membership.clone().ok_or_else(invalid)?;
        let import = membership.history_import.as_mut().ok_or_else(invalid)?;
        if import.source_device_id != sender.device_id {
            return Err(invalid());
        }
        let rows = self.history_rows(import.accept(&batch)?)?;
        self.require_history_epoch(store, roster, batch.epoch)?;
        self.commit_history_rows(store, membership, rows)?;
        self.history_last_rx_ms = super::super::super::now_ms();
        Ok(())
    }

    pub(in crate::private_dm_runtime::devices) fn require_history_epoch(
        &mut self,
        store: &Persistence,
        roster: &DeviceRoster,
        epoch: Option<u64>,
    ) -> Result<()> {
        let Some(epoch) =
            epoch.filter(|epoch| self.crypto.epoch().is_some_and(|current| *epoch > current))
        else {
            if self.awaiting_device_epoch()
                || (epoch.is_none()
                    && self
                        .membership
                        .as_ref()
                        .and_then(|m| m.topology.roster(&roster.user_id()))
                        .is_some_and(|base| roster.has_removal_since(base).unwrap_or(false)))
            {
                return Err(invalid());
            }
            return Ok(());
        };
        let mut next = self.membership.clone().ok_or_else(invalid)?;
        next.require_epoch(epoch, self.crypto.epoch().ok_or_else(invalid)?);
        self.save_recovery_membership(store, next)?;
        Err(invalid())
    }

    // Matching live rows are saved too: they can be visible before the normal
    // tail writer runs. Durable progress must never get ahead of those rows.
    pub(in crate::private_dm_runtime::devices) fn commit_history_rows(
        &mut self,
        store: &Persistence,
        membership: super::super::DeviceMembership,
        rows: Vec<StoredMessage<ChatMessage>>,
    ) -> Result<()> {
        let mut persisted = self.to_persisted_record();
        persisted.membership = Some(membership.clone());
        let json = serde_json::to_vec(&persisted).map_err(|_| invalid())?;
        store.commit_dm_history_import::<ChatMessage>(&self.session_id, &json, &rows)?;
        self.membership = Some(membership);
        for row in rows {
            if !self
                .messages
                .iter()
                .any(|message| message.message_id.as_ref() == Some(&row.message_id))
            {
                self.messages.push_stamped(row.message);
            }
        }
        Ok(())
    }

    pub(in crate::private_dm_runtime::devices) fn commit_current_history(
        &mut self,
        store: &Persistence,
        membership: super::super::DeviceMembership,
    ) -> Result<()> {
        let records = self
            .messages
            .iter()
            .filter_map(TextRecord::from_message)
            .collect();
        let rows = self.history_rows(records)?;
        self.commit_history_rows(store, membership, rows)
    }

    pub(in crate::private_dm_runtime::devices) fn history_rows(
        &self,
        records: Vec<TextRecord>,
    ) -> Result<Vec<StoredMessage<ChatMessage>>> {
        let mut rows = Vec::new();
        let mut ids = HashSet::new();
        for record in records {
            record.validate()?;
            record.validate_content(&format!("dm:{}", self.session_id))?;
            if !ids.insert(record.message_id.clone()) {
                return Err(invalid());
            }
            let existing = self
                .messages
                .iter()
                .find(|message| message.message_id.as_ref() == Some(&record.message_id));
            if let Some(existing) = existing {
                if existing
                    .metadata
                    .as_ref()
                    .is_none_or(|m| m.deletion.is_none())
                    && TextRecord::from_message(existing).as_ref() != Some(&record)
                {
                    return Err(invalid());
                }
            }
            rows.push(StoredMessage {
                conversation_id: self.session_id.clone(),
                sent_at_ms: record.sent_at_ms,
                message_id: record.message_id.clone(),
                message: existing.cloned().unwrap_or_else(|| record.into_message()),
                attachment_manifest: None,
            });
        }
        Ok(rows)
    }
}

impl PrivateDmRuntime {
    pub(in crate::private_dm_runtime) fn receive_history_batch(
        &mut self,
        identity: &DeviceIdentity,
        sender: &DeviceDescriptor,
        roster: &DeviceRoster,
        batch: HistoryBatch,
    ) -> Result<()> {
        let store = self.sessions.persistence().cloned().ok_or_else(invalid)?;
        let session = self.session_mut(&batch.session_id)?;
        session.authorize_history_device(identity, sender, roster)?;
        session.import_history_batch(&store, sender, roster, batch)
    }
}
