use super::*;

impl Persistence {
    pub(super) fn write_outbound_row(
        &self,
        tx: &redb::WriteTransaction,
        tables: HistoryTables,
        conversation_id: &str,
        message_id: &str,
        attempt: Option<&[u8]>,
    ) -> Result<(), PersistenceError> {
        let cancelled = attempt
            .map(|bytes| self.cancelled_attempt(tx, tables, conversation_id, message_id, bytes))
            .transpose()?
            .unwrap_or(false);
        let attempt = attempt.filter(|_| !cancelled);
        let key = Self::outbound_attempt_key(tables.outbound_scope, conversation_id, message_id);
        let blob = attempt
            .map(|bytes| encrypt_blob(&self.dek, bytes))
            .transpose()?;
        Self::update_row(tx, OUTBOUND_ATTEMPTS, &key, blob.as_deref())
    }

    fn cancelled_attempt(
        &self,
        tx: &redb::WriteTransaction,
        tables: HistoryTables,
        conversation_id: &str,
        message_id: &str,
        attempt: &[u8],
    ) -> Result<bool, PersistenceError> {
        let Ok(attempt) = serde_json::from_slice::<serde_json::Value>(attempt) else {
            return Ok(false);
        };
        let Some(time) = attempt.get("sent_at_ms").and_then(|v| v.as_u64()) else {
            return Ok(false);
        };
        let key = Self::history_message_key(conversation_id, time, message_id);
        let rows = tx.open_table(tables.messages).map_err(db_error)?;
        let Some(row) = rows.get(key.as_str()).map_err(db_error)? else {
            return Ok(false);
        };
        let bytes = decrypt_blob(&self.dek, row.value())?;
        let Ok(row) = serde_json::from_slice::<serde_json::Value>(&bytes) else {
            return Ok(false);
        };
        let Some(marker) = row
            .pointer("/message/metadata/deletion")
            .filter(|v| !v.is_null())
        else {
            return Ok(false);
        };
        Ok(marker.get("scope")
            == Some(&serde_json::json!(
                crate::message_deletion::DeleteScope::ForEveryone
            ))
            || attempt.get("ever_published").and_then(|v| v.as_bool()) == Some(false))
    }
}
