use super::*;

impl Persistence {
    /// Late replay/import/outbox writes cannot put content back into an erased row.
    pub(super) fn write_history_row(
        &self,
        tx: &redb::WriteTransaction,
        tables: HistoryTables,
        key: &str,
        blob: &[u8],
    ) -> Result<(), PersistenceError> {
        let existing = {
            let rows = tx.open_table(tables.messages).map_err(db_error)?;
            let bytes = rows
                .get(key)
                .map_err(db_error)?
                .map(|value| decrypt_blob(&self.dek, value.value()))
                .transpose()?;
            bytes
        };
        let existing = existing
            .as_deref()
            .map(serde_json::from_slice::<serde_json::Value>)
            .transpose()
            .map_err(|e| PersistenceError::Json(e.to_string()))?;
        if existing
            .as_ref()
            .and_then(|v| v.pointer("/message/metadata/deletion"))
            .is_some_and(|v| !v.is_null())
        {
            return Ok(());
        }
        let bytes = decrypt_blob(&self.dek, blob)?;
        let mut incoming: serde_json::Value =
            serde_json::from_slice(&bytes).map_err(|e| PersistenceError::Json(e.to_string()))?;
        if incoming.get("history_evidence").is_none_or(|v| v.is_null()) {
            if let Some(evidence) = existing.as_ref().and_then(|v| v.get("history_evidence")) {
                incoming["history_evidence"] = evidence.clone();
            }
        }
        let bytes =
            serde_json::to_vec(&incoming).map_err(|e| PersistenceError::Json(e.to_string()))?;
        let erased_bytes = self.erase_known_target(tx, tables, &bytes)?;
        let guarded = encrypt_blob(&self.dek, &erased_bytes)?;
        Self::update_row(tx, tables.messages, key, Some(&guarded))?;
        Ok(())
    }
}
