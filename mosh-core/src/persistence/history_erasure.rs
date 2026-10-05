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
        let erased = {
            let rows = tx.open_table(tables.messages).map_err(db_error)?;
            let existing = rows.get(key).map_err(db_error)?;
            match existing {
                Some(value) => {
                    let bytes = decrypt_blob(&self.dek, value.value())?;
                    serde_json::from_slice::<serde_json::Value>(&bytes)
                        .ok()
                        .as_ref()
                        .and_then(|value| value.pointer("/message/metadata/deletion"))
                        .is_some_and(|v| !v.is_null())
                }
                None => false,
            }
        };
        if !erased {
            let bytes = decrypt_blob(&self.dek, blob)?;
            let erased_bytes = self.erase_known_target(tx, tables, &bytes)?;
            let guarded = encrypt_blob(&self.dek, &erased_bytes)?;
            Self::update_row(tx, tables.messages, key, Some(&guarded))?;
        }
        Ok(())
    }
}
