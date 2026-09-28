//! Import text and its continuation cursor in one locally encrypted transaction.
use super::*;
use crate::conversation::history::StoredMessage;

impl Persistence {
    pub(crate) fn get_dm_history_message(
        &self,
        session: &str,
        sent_at_ms: u64,
        message_id: &str,
    ) -> Result<Option<Vec<u8>>, PersistenceError> {
        self.get(
            MESSAGES,
            &Self::history_message_key(session, sent_at_ms, message_id),
        )
    }

    pub(crate) fn commit_dm_history_import<M: serde::Serialize>(
        &self,
        session: &str,
        record: &[u8],
        messages: &[StoredMessage<M>],
    ) -> Result<(), PersistenceError> {
        let record = encrypt_blob(&self.dek, record)?;
        let mut rows = Vec::with_capacity(messages.len());
        for message in messages {
            let json = serde_json::to_vec(message)
                .map_err(|error| PersistenceError::Json(error.to_string()))?;
            let key = Self::history_message_key(session, message.sent_at_ms, &message.message_id);
            rows.push((key, encrypt_blob(&self.dek, &json)?));
        }
        let tx = self.db.begin_write().map_err(dm_devices::db_error)?;
        {
            let mut table = tx.open_table(MESSAGES).map_err(dm_devices::db_error)?;
            for (key, value) in &rows {
                table
                    .insert(key.as_str(), value.as_slice())
                    .map_err(dm_devices::db_error)?;
            }
            tx.open_table(SESSIONS)
                .map_err(dm_devices::db_error)?
                .insert(session, record.as_slice())
                .map_err(dm_devices::db_error)?;
        }
        tx.commit().map_err(dm_devices::db_error)
    }
}
