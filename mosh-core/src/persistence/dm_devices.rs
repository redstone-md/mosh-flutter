//! Atomic DM epoch records and race-free creation of the shared device identity.
use super::*;

pub(super) fn db_error(error: impl std::fmt::Display) -> PersistenceError {
    PersistenceError::Db(error.to_string())
}

impl Persistence {
    /// Compare the decrypted record in the write transaction so two runtime
    /// owners cannot roll back each other's roster or pairing delivery state.
    pub(crate) fn replace_device_link(
        &self,
        expected: &[u8],
        replacement: &[u8],
    ) -> Result<bool, PersistenceError> {
        let encrypted = encrypt_blob(&self.dek, replacement)?;
        let tx = self.db.begin_write().map_err(db_error)?;
        {
            let mut table = tx.open_table(DEVICE_LINK).map_err(db_error)?;
            let current = table
                .get(DEVICE_LINK_KEY)
                .map_err(db_error)?
                .map(|row| row.value().to_vec());
            if current
                .map(|row| decrypt_blob(&self.dek, &row))
                .transpose()?
                .as_deref()
                != Some(expected)
            {
                return Ok(false);
            }
            table
                .insert(DEVICE_LINK_KEY, encrypted.as_slice())
                .map_err(db_error)?;
        }
        tx.commit().map_err(db_error)?;
        Ok(true)
    }

    pub(crate) fn put_dm_transition(
        &self,
        session: &str,
        record: &[u8],
        snapshot: &[u8],
    ) -> Result<(), PersistenceError> {
        let record = encrypt_blob(&self.dek, record)?;
        let snapshot = encrypt_blob(&self.dek, snapshot)?;
        let tx = self.db.begin_write().map_err(db_error)?;
        {
            tx.open_table(SESSIONS)
                .map_err(db_error)?
                .insert(session, record.as_slice())
                .map_err(db_error)?;
            tx.open_table(MLS_SNAPSHOT)
                .map_err(db_error)?
                .insert(session, snapshot.as_slice())
                .map_err(db_error)?;
        }
        tx.commit().map_err(db_error)
    }

    /// Concurrent initial readers must receive the same identity winner.
    pub(crate) fn initialize_device_link(
        &self,
        candidate: &[u8],
    ) -> Result<Vec<u8>, PersistenceError> {
        let encrypted = encrypt_blob(&self.dek, candidate)?;
        let tx = self.db.begin_write().map_err(db_error)?;
        let winner = {
            let mut table = tx.open_table(DEVICE_LINK).map_err(db_error)?;
            let existing = table
                .get(DEVICE_LINK_KEY)
                .map_err(db_error)?
                .map(|row| row.value().to_vec());
            match existing {
                Some(row) => decrypt_blob(&self.dek, &row)?,
                None => {
                    table
                        .insert(DEVICE_LINK_KEY, encrypted.as_slice())
                        .map_err(db_error)?;
                    candidate.to_vec()
                }
            }
        };
        tx.commit().map_err(db_error)?;
        Ok(winner)
    }
}
