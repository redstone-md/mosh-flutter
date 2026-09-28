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
        batch: HistoryBatch,
    ) -> Result<()> {
        let mut membership = self.membership.clone().ok_or_else(invalid)?;
        let import = membership.history_import.as_mut().ok_or_else(invalid)?;
        if import.source_device_id != sender.device_id {
            return Err(invalid());
        }
        let rows = self.history_rows(import.accept(&batch)?)?;
        let mut persisted = self.to_persisted_record();
        persisted.membership = Some(membership.clone());
        let json = serde_json::to_vec(&persisted).map_err(|_| invalid())?;
        store.commit_dm_history_import::<ChatMessage>(&self.session_id, &json, &rows)?;
        self.membership = Some(membership);
        self.history_last_rx_ms = super::super::super::now_ms();
        for row in rows {
            self.messages.push_stamped(row.message);
        }
        Ok(())
    }

    pub(in crate::private_dm_runtime::devices) fn history_rows(
        &self,
        records: Vec<TextRecord>,
    ) -> Result<Vec<StoredMessage<ChatMessage>>> {
        let mut rows = Vec::new();
        let mut ids = HashSet::new();
        for record in records {
            record.validate()?;
            if !ids.insert(record.message_id.clone()) {
                return Err(invalid());
            }
            if let Some(existing) = self
                .messages
                .iter()
                .find(|message| message.message_id.as_ref() == Some(&record.message_id))
            {
                if TextRecord::from_message(existing).as_ref() != Some(&record) {
                    return Err(invalid());
                }
                continue;
            }
            rows.push(StoredMessage {
                conversation_id: self.session_id.clone(),
                sent_at_ms: record.sent_at_ms,
                message_id: record.message_id.clone(),
                message: record.into_message(),
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
        session.import_history_batch(&store, sender, batch)
    }
}
