//! Shared history operations; table selection is data.
use super::*;

impl Persistence {
    pub fn put_conversation(
        &self,
        tables: HistoryTables,
        conversation_id: &str,
        json: &[u8],
    ) -> Result<(), PersistenceError> {
        self.put(tables.conversations, conversation_id, json)
    }

    pub fn list_conversations(
        &self,
        tables: HistoryTables,
    ) -> Result<Vec<Vec<u8>>, PersistenceError> {
        let rtx = self.db.begin_read().map_err(db_error)?;
        let t = rtx.open_table(tables.conversations).map_err(db_error)?;
        let mut out = Vec::new();
        for item in t.iter().map_err(db_error)? {
            let (k, v) = item.map_err(db_error)?;
            match decrypt_blob(&self.dek, v.value()) {
                Ok(plain) => out.push(plain),
                Err(e) => dlog::write(
                    LogLevel::Warn,
                    kinds::PERSIST,
                    tables.label,
                    &format!(
                        "skipping undecryptable {} row {}: {e}",
                        tables.label,
                        k.value()
                    ),
                ),
            }
        }
        Ok(out)
    }

    pub fn append_history_message(
        &self,
        tables: HistoryTables,
        conversation_id: &str,
        sent_at_ms: u64,
        message_id: &str,
        json: &[u8],
    ) -> Result<(), PersistenceError> {
        let key = Self::history_message_key(conversation_id, sent_at_ms, message_id);
        self.put(tables.messages, &key, json)
    }

    pub(super) fn history_message_key(
        conversation_id: &str,
        sent_at_ms: u64,
        message_id: &str,
    ) -> String {
        format!("{conversation_id}\u{0001}{sent_at_ms:020}\u{0001}{message_id}")
    }

    pub fn list_history_messages(
        &self,
        tables: HistoryTables,
        conversation_id: &str,
    ) -> Result<Vec<Vec<u8>>, PersistenceError> {
        self.range_prefix(tables.messages, conversation_id)
    }

    /// Remove a conversation and its outbound work in one transaction.
    pub(super) fn delete_conversation(
        &self,
        tables: HistoryTables,
        id: &str,
    ) -> Result<(), PersistenceError> {
        self.write(|tx| {
            Self::update_row(tx, tables.conversations, id, None)?;
            if let Some(snapshot) = tables.snapshots {
                Self::update_row(tx, snapshot, id, None)?;
            }
            self.delete_prefix(tx, tables.messages, id)?;
            self.delete_prefix(
                tx,
                OUTBOUND_ATTEMPTS,
                &Self::outbound_attempt_prefix(tables.outbound_scope, id),
            )
        })
    }
}
