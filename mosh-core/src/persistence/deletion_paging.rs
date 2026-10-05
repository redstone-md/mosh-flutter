use super::*;
use crate::message_deletion::DeletionRecord;
use std::ops::Bound;

impl Persistence {
    pub(crate) fn account_deletion_page(
        &self,
        user: &str,
        after: Option<&str>,
    ) -> Result<(Vec<DeletionRecord>, Option<String>), PersistenceError> {
        let tx = self.db.begin_read().map_err(db_error)?;
        let table = tx.open_table(MESSAGE_DELETIONS).map_err(db_error)?;
        let start = after.map_or(Bound::Unbounded, Bound::Excluded);
        let mut page = Vec::new();
        let mut bytes = 0;
        let mut next = None;
        for row in table
            .range::<&str>((start, Bound::Unbounded))
            .map_err(db_error)?
        {
            let (_, value) = row.map_err(db_error)?;
            let record: DeletionRecord =
                serde_json::from_slice(&decrypt_blob(&self.dek, value.value())?)
                    .map_err(|e| PersistenceError::Json(e.to_string()))?;
            if !record.visible_to_account(user) {
                continue;
            }
            let size = serde_json::to_vec(&record)
                .map_err(|e| PersistenceError::Json(e.to_string()))?
                .len();
            if !page.is_empty() && (page.len() == 16 || bytes + size > 24000) {
                next = page.last().map(DeletionRecord::storage_key);
                break;
            }
            bytes += size;
            page.push(record);
        }
        Ok((page, next))
    }
}
