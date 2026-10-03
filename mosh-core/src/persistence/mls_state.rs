//! Keep the conversation record and its own MLS snapshot in one accepted write.
use super::{dm_devices::db_error, *};

impl Persistence {
    pub(crate) fn put_dm_transition(
        &self,
        session: &str,
        record: &[u8],
        snapshot: &[u8],
    ) -> Result<(), PersistenceError> {
        self.put_mls_state(SESSIONS, MLS_SNAPSHOT, session, record, snapshot)
    }

    pub(crate) fn put_group_transition(
        &self,
        group: &str,
        record: &[u8],
        snapshot: &[u8],
    ) -> Result<(), PersistenceError> {
        self.put_mls_state(GROUPS, GROUP_MLS_SNAPSHOT, group, record, snapshot)
    }

    fn put_mls_state(
        &self,
        records: Rows,
        snapshots: Rows,
        id: &str,
        record: &[u8],
        snapshot: &[u8],
    ) -> Result<(), PersistenceError> {
        let record = encrypt_blob(&self.dek, record)?;
        let snapshot = encrypt_blob(&self.dek, snapshot)?;
        let tx = self.db.begin_write().map_err(db_error)?;
        {
            tx.open_table(records)
                .map_err(db_error)?
                .insert(id, record.as_slice())
                .map_err(db_error)?;
            tx.open_table(snapshots)
                .map_err(db_error)?
                .insert(id, snapshot.as_slice())
                .map_err(db_error)?;
        }
        tx.commit().map_err(db_error)
    }
}
