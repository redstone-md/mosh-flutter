//! Accept shared-name state and its history events in one encrypted transaction.
use super::*;

impl Persistence {
    pub(crate) fn put_group_name(
        &self,
        group: &str,
        record: &[u8],
        snapshot: &[u8],
        messages: &[crate::private_group_runtime::GroupMessage],
    ) -> Result<(), PersistenceError> {
        let record = encrypt_blob(&self.dek, record)?;
        let snapshot = encrypt_blob(&self.dek, snapshot)?;
        let events = messages
            .iter()
            .map(|message| self.encrypt_name_event(group, message))
            .collect::<Result<Vec<_>, _>>()?;
        self.write(|tx| {
            Self::update_row(tx, GROUPS, group, Some(&record))?;
            Self::update_row(tx, GROUP_MLS_SNAPSHOT, group, Some(&snapshot))?;
            for (key, event) in &events {
                Self::update_row(tx, GROUP_MESSAGES, key, Some(event))?;
            }
            Ok(())
        })
    }

    fn encrypt_name_event(
        &self,
        group: &str,
        message: &crate::private_group_runtime::GroupMessage,
    ) -> Result<(String, Vec<u8>), PersistenceError> {
        let id = message
            .message_id
            .as_deref()
            .ok_or_else(|| PersistenceError::Json("missing name event id".into()))?;
        let key = Self::history_message_key(group, message.sent_at_ms.unwrap_or_default(), id);
        let event = crate::conversation::history::StoredMessage {
            conversation_id: group.to_owned(),
            sent_at_ms: message.sent_at_ms.unwrap_or_default(),
            message_id: id.to_owned(),
            message: message.clone(),
            attachment_manifest: None,
            preview_manifest: None,
        };
        let event =
            serde_json::to_vec(&event).map_err(|e| PersistenceError::Json(e.to_string()))?;
        Ok((key, encrypt_blob(&self.dek, &event)?))
    }
}
