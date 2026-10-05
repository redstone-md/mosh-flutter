use super::*;
use crate::message_deletion::DeletionRecord;

impl Persistence {
    pub(super) fn merge_deletion_row(
        &self,
        tx: &redb::WriteTransaction,
        incoming: &DeletionRecord,
    ) -> Result<(), PersistenceError> {
        let key = incoming.storage_key();
        let record = {
            let table = tx.open_table(MESSAGE_DELETIONS).map_err(db_error)?;
            let existing = table.get(key.as_str()).map_err(db_error)?;
            match existing {
                Some(row) => {
                    let current: DeletionRecord =
                        serde_json::from_slice(&decrypt_blob(&self.dek, row.value())?)
                            .map_err(|e| PersistenceError::Json(e.to_string()))?;
                    current.merged(incoming)
                }
                None => incoming.clone(),
            }
        };
        let blob = encrypt_blob(
            &self.dek,
            &serde_json::to_vec(&record).map_err(|e| PersistenceError::Json(e.to_string()))?,
        )?;
        Self::update_row(tx, MESSAGE_DELETIONS, &key, Some(&blob))
    }
}
