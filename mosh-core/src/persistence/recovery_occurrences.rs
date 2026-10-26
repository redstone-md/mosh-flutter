//! Occurrence conflicts are checked in the cursor's transaction.
use super::*;
use crate::conversation::{history::StoredMessage, recovery::occurrence::Occurrence};
use serde::de::DeserializeOwned;

impl Persistence {
    pub(super) fn admit_occurrence(
        &self,
        tx: &redb::WriteTransaction,
        tables: HistoryTables,
        id: &str,
        occurrence: &Occurrence,
    ) -> Result<(), PersistenceError> {
        let key = format!("{}:{id}\u{1}{}", tables.label, occurrence.native_id);
        let mut table = tx.open_table(CONVERSATION_OCCURRENCES).map_err(db_error)?;
        let old = table
            .get(key.as_str())
            .map_err(db_error)?
            .map(|v| decrypt_blob(&self.dek, v.value()))
            .transpose()?;
        if let Some(old) = old {
            let old: Occurrence =
                serde_json::from_slice(&old).map_err(|e| PersistenceError::Json(e.to_string()))?;
            if old != *occurrence {
                return Err(PersistenceError::Json(
                    "conflicting native history occurrence".into(),
                ));
            }
            return Ok(());
        }
        let bytes =
            serde_json::to_vec(occurrence).map_err(|e| PersistenceError::Json(e.to_string()))?;
        let bytes = encrypt_blob(&self.dek, &bytes)?;
        table
            .insert(key.as_str(), bytes.as_slice())
            .map_err(db_error)?;
        Ok(())
    }

    pub(crate) fn prepare_history_occurrences<M: DeserializeOwned>(
        &self,
        tables: HistoryTables,
        id: &str,
        select: impl Fn(&StoredMessage<M>) -> Result<Option<Occurrence>, String>,
    ) -> Result<(), PersistenceError> {
        let marker = format!("{}:{id}\u{1}occurrences-ready", tables.label);
        if self.get(CONVERSATION_RECOVERY, &marker)?.is_some() {
            return Ok(());
        }
        self.write(|tx| {
            let table = tx.open_table(tables.messages).map_err(db_error)?;
            let prefix = format!("{id}\u{1}");
            for row in table
                .range(prefix.as_str()..format!("{prefix}\u{10ffff}").as_str())
                .map_err(db_error)?
            {
                let (_, value) = row.map_err(db_error)?;
                let row = serde_json::from_slice::<StoredMessage<M>>(&decrypt_blob(
                    &self.dek,
                    value.value(),
                )?)
                .map_err(|e| PersistenceError::Json(e.to_string()))?;
                if let Some(occurrence) = select(&row).map_err(PersistenceError::Json)? {
                    self.admit_occurrence(tx, tables, id, &occurrence)?;
                }
            }
            Self::update_row(
                tx,
                CONVERSATION_RECOVERY,
                &marker,
                Some(&encrypt_blob(&self.dek, b"1")?),
            )
        })
    }
}
