//! Keep the conversation record and its own MLS snapshot in one accepted write.
use super::*;

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
        self.write(|tx| {
            Self::update_row(tx, records, id, Some(&record))?;
            Self::update_row(tx, snapshots, id, Some(&snapshot))
        })
    }
}
