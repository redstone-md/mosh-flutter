//! Key acquisition and the shared encrypted row transaction boundary.
use super::*;
use crate::secure_storage::{OsSecureSecretStore, SecureSecretStore};
use rand::RngCore;
use std::path::Path;

const DEK_KEY: &str = "history-dek-v1";

#[cfg(target_os = "macos")]
fn dek_store(path: &Path) -> Box<dyn SecureSecretStore> {
    match path.parent() {
        Some(dir) => Box::new(crate::file_secret_store::FileSecretStore::new(dir)),
        None => Box::new(OsSecureSecretStore),
    }
}

#[cfg(not(target_os = "macos"))]
fn dek_store(_path: &Path) -> Box<dyn SecureSecretStore> {
    Box::new(OsSecureSecretStore)
}

impl Persistence {
    pub fn open(path: &Path) -> Result<Self, PersistenceError> {
        Self::open_with_key(path, DEK_KEY)
    }

    /// Tests use an isolated keychain key so cleanup cannot orphan real history.
    pub(crate) fn open_with_key(path: &Path, dek_key: &str) -> Result<Self, PersistenceError> {
        let store = dek_store(path);
        let db_exists = path.exists();
        let dek = match store.load_secret(dek_key) {
            Ok(bytes) => bytes.try_into().map_err(|_| {
                PersistenceError::Keychain("stored DEK has unexpected length".into())
            })?,
            Err(e) => {
                if db_exists {
                    return Err(PersistenceError::Keychain(format!(
                        "DEK unavailable but database exists: {e}"
                    )));
                }
                let mut d = [0u8; 32];
                rand::rngs::OsRng.fill_bytes(&mut d);
                store
                    .save_secret(dek_key, &d)
                    .map_err(|err| PersistenceError::Keychain(err.to_string()))?;
                d
            }
        };
        Self::open_with_dek(path, dek)
    }

    /// Open with a host-supplied DEK. A wrong key fails on decryption.
    pub fn open_with_dek(path: &Path, dek: [u8; 32]) -> Result<Self, PersistenceError> {
        let db = Database::create(path).map_err(db_error)?;
        let store = Self { db, dek };
        store.write(|tx| {
            for table in ALL_TABLES {
                tx.open_table(table).map_err(db_error)?;
            }
            store.initialize_deletion_index(tx)?;
            Ok(())
        })?;
        Ok(store)
    }

    pub(super) fn write<T>(
        &self,
        operation: impl FnOnce(&redb::WriteTransaction) -> Result<T, PersistenceError>,
    ) -> Result<T, PersistenceError> {
        let tx = self.db.begin_write().map_err(db_error)?;
        let result = operation(&tx)?;
        tx.commit().map_err(db_error)?;
        Ok(result)
    }

    /// Update an already encrypted row inside its caller's atomic write.
    pub(super) fn update_row(
        tx: &redb::WriteTransaction,
        table: Rows,
        key: &str,
        blob: Option<&[u8]>,
    ) -> Result<(), PersistenceError> {
        let mut rows = tx.open_table(table).map_err(db_error)?;
        match blob {
            Some(blob) => {
                rows.insert(key, blob).map_err(db_error)?;
            }
            None => {
                rows.remove(key).map_err(db_error)?;
            }
        }
        Ok(())
    }

    pub(super) fn put(
        &self,
        table: Rows,
        key: &str,
        plaintext: &[u8],
    ) -> Result<(), PersistenceError> {
        let blob = encrypt_blob(&self.dek, plaintext)?;
        self.write(|tx| Self::update_row(tx, table, key, Some(&blob)))
    }

    pub(super) fn get(&self, table: Rows, key: &str) -> Result<Option<Vec<u8>>, PersistenceError> {
        let tx = self.db.begin_read().map_err(db_error)?;
        let rows = tx.open_table(table).map_err(db_error)?;
        rows.get(key)
            .map_err(db_error)?
            .map(|row| decrypt_blob(&self.dek, row.value()))
            .transpose()
    }

    pub(super) fn list_rows(
        &self,
        table: Rows,
    ) -> Result<Vec<(String, Vec<u8>)>, PersistenceError> {
        let tx = self.db.begin_read().map_err(db_error)?;
        let rows = tx.open_table(table).map_err(db_error)?;
        rows.iter()
            .map_err(db_error)?
            .map(|row| {
                let (key, value) = row.map_err(db_error)?;
                Ok((
                    key.value().to_string(),
                    decrypt_blob(&self.dek, value.value())?,
                ))
            })
            .collect()
    }

    pub(super) fn prefix_range(prefix: &str) -> std::ops::Range<String> {
        format!("{prefix}\u{0001}")..format!("{prefix}\u{0002}")
    }

    pub(super) fn range_prefix(
        &self,
        table: Rows,
        prefix: &str,
    ) -> Result<Vec<Vec<u8>>, PersistenceError> {
        let range = Self::prefix_range(prefix);
        let tx = self.db.begin_read().map_err(db_error)?;
        let rows = tx.open_table(table).map_err(db_error)?;
        rows.range(range.start.as_str()..range.end.as_str())
            .map_err(db_error)?
            .map(|row| decrypt_blob(&self.dek, row.map_err(db_error)?.1.value()))
            .collect()
    }

    pub(super) fn delete_prefix(
        &self,
        tx: &redb::WriteTransaction,
        table: Rows,
        prefix: &str,
    ) -> Result<(), PersistenceError> {
        let range = Self::prefix_range(prefix);
        tx.open_table(table)
            .map_err(db_error)?
            .retain_in(range.start.as_str()..range.end.as_str(), |_, _| false)
            .map_err(db_error)
    }
}
