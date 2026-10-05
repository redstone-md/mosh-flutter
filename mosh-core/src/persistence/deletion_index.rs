use super::*;
use crate::message_deletion::DeletionRecord;

const READY: &str = "\0ready-v1";

impl Persistence {
    pub(super) fn initialize_deletion_index(
        &self,
        tx: &redb::WriteTransaction,
    ) -> Result<(), PersistenceError> {
        let ready = {
            let table = tx.open_table(MESSAGE_DELETION_TARGETS).map_err(db_error)?;
            let ready = table.get(READY).map_err(db_error)?.is_some();
            ready
        };
        if ready {
            return Ok(());
        }
        let rows = tx.open_table(MESSAGE_DELETIONS).map_err(db_error)?;
        for row in rows.iter().map_err(db_error)? {
            let (_, value) = row.map_err(db_error)?;
            let record = serde_json::from_slice(&decrypt_blob(&self.dek, value.value())?)
                .map_err(|e| PersistenceError::Json(e.to_string()))?;
            self.index_deletion(tx, &record)?;
        }
        Self::update_row(
            tx,
            MESSAGE_DELETION_TARGETS,
            READY,
            Some(&encrypt_blob(&self.dek, b"v1")?),
        )
    }

    pub(super) fn index_deletion(
        &self,
        tx: &redb::WriteTransaction,
        record: &DeletionRecord,
    ) -> Result<(), PersistenceError> {
        let row_key = record.storage_key();
        let blob = encrypt_blob(&self.dek, row_key.as_bytes())?;
        for target in std::iter::once(&record.key).chain(record.personal_correlation.iter()) {
            let key = format!("{}\u{0001}{target}\u{0001}{row_key}", record.context);
            Self::update_row(tx, MESSAGE_DELETION_TARGETS, &key, Some(&blob))?;
        }
        Ok(())
    }

    pub(super) fn deletion_target_records(
        &self,
        tx: &redb::WriteTransaction,
        context: &str,
        target: &str,
    ) -> Result<Vec<DeletionRecord>, PersistenceError> {
        let range = Self::prefix_range(&format!("{context}\u{0001}{target}"));
        let index = tx.open_table(MESSAGE_DELETION_TARGETS).map_err(db_error)?;
        let records = tx.open_table(MESSAGE_DELETIONS).map_err(db_error)?;
        let mut result = Vec::new();
        for row in index
            .range(range.start.as_str()..range.end.as_str())
            .map_err(db_error)?
        {
            let (_, value) = row.map_err(db_error)?;
            let key = String::from_utf8(decrypt_blob(&self.dek, value.value())?)
                .map_err(|e| PersistenceError::Json(e.to_string()))?;
            if let Some(record) = records.get(key.as_str()).map_err(db_error)? {
                result.push(
                    serde_json::from_slice(&decrypt_blob(&self.dek, record.value())?)
                        .map_err(|e| PersistenceError::Json(e.to_string()))?,
                );
            }
        }
        Ok(result)
    }
}
