//! Encrypted frozen source keys and atomic shared history continuation.
use super::*;
use crate::conversation::history::StoredMessage;
use crate::conversation::recovery::manifest::{HistoryKey, Manifest};
use crate::conversation::recovery::occurrence::Occurrence;
use serde::{de::DeserializeOwned, Serialize};
use sha2::{Digest, Sha256};

impl Persistence {
    #[allow(
        dead_code,
        reason = "Approved shared reader for the parallel IVO-142 group adapter."
    )]
    pub(crate) fn group_history_evidence<R: DeserializeOwned>(
        &self,
        key: &str,
    ) -> Result<Option<R>, PersistenceError> {
        self.get(GROUP_HISTORY_EVIDENCE, key)?
            .map(|bytes| serde_json::from_slice(&bytes).map_err(json_error))
            .transpose()
    }

    pub(crate) fn recovery_state<R: DeserializeOwned>(
        &self,
        key: &str,
    ) -> Result<Option<R>, PersistenceError> {
        self.get(CONVERSATION_RECOVERY, key)?
            .map(|b| serde_json::from_slice(&b).map_err(|e| PersistenceError::Json(e.to_string())))
            .transpose()
    }

    pub(crate) fn save_recovery<R: Serialize>(
        &self,
        key: &str,
        state: &R,
    ) -> Result<(), PersistenceError> {
        self.put(
            CONVERSATION_RECOVERY,
            key,
            &serde_json::to_vec(state).map_err(json_error)?,
        )
    }

    pub(crate) fn commit_history_recovery<M: Serialize, R: Serialize>(
        &self,
        tables: HistoryTables,
        id: &str,
        checkpoint_key: &str,
        checkpoint: &R,
        messages: &[StoredMessage<M>],
        occurrences: &[Occurrence],
    ) -> Result<(), PersistenceError> {
        let state = serde_json::to_vec(checkpoint).map_err(json_error)?;
        self.commit_history_admission(
            tables,
            id,
            HistoryAdmission {
                checkpoint: Some((checkpoint_key, &state)),
                occurrences,
                ..Default::default()
            },
            messages,
        )
    }

    pub(crate) fn history_message<M: DeserializeOwned>(
        &self,
        tables: HistoryTables,
        id: &str,
        key: &HistoryKey,
    ) -> Result<Option<StoredMessage<M>>, PersistenceError> {
        self.get(
            tables.messages,
            &Self::history_message_key(id, key.sent_at_ms, &key.message_id),
        )?
        .map(|b| serde_json::from_slice(&b).map_err(json_error))
        .transpose()
    }

    pub(crate) fn recovery_manifest<M: DeserializeOwned>(
        &self,
        tables: HistoryTables,
        id: &str,
        select: impl Fn(&StoredMessage<M>) -> Result<Option<HistoryKey>, String>,
    ) -> Result<Manifest, PersistenceError> {
        let tx = self.db.begin_read().map_err(db_error)?;
        let table = tx.open_table(tables.messages).map_err(db_error)?;
        let mut hash = Sha256::new();
        hash.update(b"[");
        let mut total = 0;
        let prefix = format!("{id}\u{1}");
        for row in table
            .range(prefix.as_str()..format!("{prefix}\u{10ffff}").as_str())
            .map_err(db_error)?
        {
            let (_, value) = row.map_err(db_error)?;
            let message: StoredMessage<M> =
                serde_json::from_slice(&decrypt_blob(&self.dek, value.value())?)
                    .map_err(json_error)?;
            if let Some(key) = select(&message).map_err(PersistenceError::Json)? {
                if total > 0 {
                    hash.update(b",");
                }
                hash.update(serde_json::to_vec(&key).map_err(json_error)?);
                total += 1;
            }
        }
        hash.update(b"]");
        Ok(Manifest {
            digest: hex::encode(hash.finalize()),
            total,
        })
    }

    pub(crate) fn freeze_recovery<M: DeserializeOwned, R: Serialize>(
        &self,
        tables: HistoryTables,
        id: &str,
        export: FrozenExport<'_, R>,
        select: impl Fn(&StoredMessage<M>) -> Result<Option<HistoryKey>, String>,
        journal: impl Iterator<Item = crate::message_deletion::DeletionRecord>,
    ) -> Result<(), PersistenceError> {
        self.write(|tx| {
            self.reserve_recovery_export(
                tx,
                export.meta_key,
                export.prefix,
                crate::conversation::now_ms(),
            )?;
            self.delete_prefix(
                tx,
                CONVERSATION_RECOVERY,
                &format!("{}\u{1}", export.prefix),
            )?;
            self.freeze_history_rows(tx, tables, id, export.prefix, select)?;
            for record in journal {
                let key = format!("{}\u{1}journal\u{1}{}", export.prefix, record.storage_key());
                let bytes =
                    encrypt_blob(&self.dek, &serde_json::to_vec(&record).map_err(json_error)?)?;
                Self::update_row(tx, CONVERSATION_RECOVERY, &key, Some(&bytes))?;
            }
            let bytes = encrypt_blob(
                &self.dek,
                &serde_json::to_vec(export.header).map_err(json_error)?,
            )?;
            Self::update_row(tx, CONVERSATION_RECOVERY, export.meta_key, Some(&bytes))
        })
    }

    fn freeze_history_rows<M: DeserializeOwned>(
        &self,
        tx: &redb::WriteTransaction,
        tables: HistoryTables,
        id: &str,
        prefix: &str,
        select: impl Fn(&StoredMessage<M>) -> Result<Option<HistoryKey>, String>,
    ) -> Result<(), PersistenceError> {
        let table = tx.open_table(tables.messages).map_err(db_error)?;
        let mut total = 0;
        let history_prefix = format!("{id}\u{1}");
        for row in table
            .range(history_prefix.as_str()..format!("{history_prefix}\u{10ffff}").as_str())
            .map_err(db_error)?
        {
            let (_, value) = row.map_err(db_error)?;
            let message: StoredMessage<M> =
                serde_json::from_slice(&decrypt_blob(&self.dek, value.value())?)
                    .map_err(json_error)?;
            if let Some(key) = select(&message).map_err(PersistenceError::Json)? {
                let bytes =
                    encrypt_blob(&self.dek, &serde_json::to_vec(&key).map_err(json_error)?)?;
                Self::update_row(
                    tx,
                    CONVERSATION_RECOVERY,
                    &format!("{prefix}\u{1}keys\u{1}{total:020}"),
                    Some(&bytes),
                )?;
                total += 1;
            }
        }
        Ok(())
    }
}

pub(crate) struct FrozenExport<'a, R> {
    pub prefix: &'a str,
    pub meta_key: &'a str,
    pub header: &'a R,
}

fn json_error(error: serde_json::Error) -> PersistenceError {
    PersistenceError::Json(error.to_string())
}
