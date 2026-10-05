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
        self.write(|tx| {
            for (key, value) in &rows {
                self.write_history_row(tx, DM_HISTORY, key, value)?;
            }
            Self::update_row(tx, SESSIONS, session, Some(&record))
        })
    }
}
