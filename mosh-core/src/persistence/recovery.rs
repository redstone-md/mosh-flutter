//! Encrypted frozen source keys and atomic shared history continuation.
use super::*;
use crate::conversation::history::StoredMessage;
use crate::conversation::recovery::manifest::{HistoryKey, Manifest, ManifestHash};
use serde::{de::DeserializeOwned, Serialize};

impl Persistence {
    /// Untrusted future associations cannot grow the protected evidence table.
    /// Accepted native evidence uses the ordinary atomic admission instead.
    pub(crate) fn save_pending_group_evidence(
        &self,
        prefix: &str,
        key: &str,
        bytes: &[u8],
    ) -> Result<(), PersistenceError> {
        if !key.starts_with(prefix) || bytes.len() > 256 * 1024 {
            return Err(PersistenceError::Json(
                "pending evidence exceeds bounds".into(),
            ));
        }
        let encrypted = encrypt_blob(&self.dek, bytes)?;
        self.write(|tx| {
            let mut table = tx.open_table(GROUP_HISTORY_EVIDENCE).map_err(db_error)?;
            let mut retained = Vec::new();
            for row in table
                .range(prefix..format!("{prefix}\u{10ffff}").as_str())
                .map_err(db_error)?
            {
                let (old_key, value) = row.map_err(db_error)?;
                if old_key.value() != key {
                    retained.push((old_key.value().to_owned(), value.value().len()));
                }
            }
            let mut size = retained.iter().map(|(_, size)| *size).sum::<usize>() + encrypted.len();
            let mut count = retained.len() + 1;
            for (old_key, old_size) in retained {
                if count <= 32 && size <= 1024 * 1024 {
                    break;
                }
                table.remove(old_key.as_str()).map_err(db_error)?;
                count -= 1;
                size -= old_size;
            }
            table.insert(key, encrypted.as_slice()).map_err(db_error)?;
            Ok(())
        })
    }

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

    pub(crate) fn history_row<M: DeserializeOwned>(
        &self,
        tables: HistoryTables,
        key: &str,
    ) -> Result<Option<StoredMessage<M>>, PersistenceError> {
        self.get(tables.messages, key)?
            .map(|bytes| serde_json::from_slice(&bytes).map_err(json_error))
            .transpose()
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
        let mut hash =
            ManifestHash::new(&format!("{}:{id}", tables.label)).map_err(PersistenceError::Json)?;
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
                hash.push(&key).map_err(PersistenceError::Json)?;
            }
        }
        Ok(hash.finish())
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
            self.delete_prefix(tx, CONVERSATION_RECOVERY, export.prefix)?;
            let frozen = self.freeze_history_rows(tx, tables, id, export.prefix, select)?;
            if &frozen != export.manifest {
                return Err(PersistenceError::Json(
                    "history Offer changed before freeze".into(),
                ));
            }
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
    ) -> Result<Manifest, PersistenceError> {
        let table = tx.open_table(tables.messages).map_err(db_error)?;
        let mut hash =
            ManifestHash::new(&format!("{}:{id}", tables.label)).map_err(PersistenceError::Json)?;
        let history_prefix = format!("{id}\u{1}");
        for row in table
            .range(history_prefix.as_str()..format!("{history_prefix}\u{10ffff}").as_str())
            .map_err(db_error)?
        {
            let (stored_key, value) = row.map_err(db_error)?;
            let message: StoredMessage<M> =
                serde_json::from_slice(&decrypt_blob(&self.dek, value.value())?)
                    .map_err(json_error)?;
            if let Some(key) = select(&message).map_err(PersistenceError::Json)? {
                let index = hash.push(&key).map_err(PersistenceError::Json)?;
                let frozen = crate::conversation::recovery::manifest::FrozenKey {
                    key,
                    row_key: stored_key.value().into(),
                };
                let bytes =
                    encrypt_blob(&self.dek, &serde_json::to_vec(&frozen).map_err(json_error)?)?;
                Self::update_row(
                    tx,
                    CONVERSATION_RECOVERY,
                    &format!("{prefix}\u{1}keys\u{1}{index:020}"),
                    Some(&bytes),
                )?;
            }
        }
        Ok(hash.finish())
    }
}

pub(crate) struct FrozenExport<'a, R> {
    pub prefix: &'a str,
    pub meta_key: &'a str,
    pub header: &'a R,
    pub manifest: &'a Manifest,
}

fn json_error(error: serde_json::Error) -> PersistenceError {
    PersistenceError::Json(error.to_string())
}
