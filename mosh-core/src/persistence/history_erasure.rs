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
            .and_then(|bytes| serde_json::from_slice::<serde_json::Value>(bytes).ok());
        if existing
            .as_ref()
            .and_then(|v| v.pointer("/message/metadata/deletion"))
            .is_some_and(|v| !v.is_null())
        {
            return Ok(());
        }
        let bytes = retain_history_evidence(decrypt_blob(&self.dek, blob)?, existing.as_ref())?;
        let erased_bytes = self.erase_known_target(tx, tables, &bytes)?;
        let guarded = encrypt_blob(&self.dek, &erased_bytes)?;
        Self::update_row(tx, tables.messages, key, Some(&guarded))?;
        Ok(())
    }
}

/// The legacy byte-store contract remains opaque unless a typed proof must survive.
fn retain_history_evidence(
    bytes: Vec<u8>,
    existing: Option<&serde_json::Value>,
) -> Result<Vec<u8>, PersistenceError> {
    let Some(evidence) = existing
        .and_then(|value| value.get("history_evidence"))
        .filter(|value| !value.is_null())
    else {
        return Ok(bytes);
    };
    let mut incoming: serde_json::Value =
        serde_json::from_slice(&bytes).map_err(|e| PersistenceError::Json(e.to_string()))?;
    let object = incoming.as_object_mut().ok_or_else(|| {
        PersistenceError::Json("typed history evidence requires a message row".into())
    })?;
    if object.get("history_evidence").is_some_and(|v| !v.is_null()) {
        return Ok(bytes);
    }
    object.insert("history_evidence".into(), evidence.clone());
    serde_json::to_vec(&incoming).map_err(|e| PersistenceError::Json(e.to_string()))
}
