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

    /// Puts down `session`'s record and snapshot unless the store holds
    /// them already, for a save that must only be on disk by the time it
    /// returns. A pair it holds is not written again, and so does not retire
    /// org offers the way [`Self::put_dm_transition`] does.
    pub(crate) fn keep_dm_transition(
        &self,
        session: &str,
        record: &[u8],
        snapshot: &[u8],
    ) -> Result<(), PersistenceError> {
        if self.holds_dm_transition(session, record, snapshot)? {
            return Ok(());
        }
        self.put_dm_transition(session, record, snapshot)
    }

    /// Whether the store holds this record and snapshot for `session`.
    fn holds_dm_transition(
        &self,
        session: &str,
        record: &[u8],
        snapshot: &[u8],
    ) -> Result<bool, PersistenceError> {
        let tx = self.db.begin_read().map_err(db_error)?;
        let holds = |table: Rows, expected: &[u8]| -> Result<bool, PersistenceError> {
            let rows = tx.open_table(table).map_err(db_error)?;
            let Some(row) = rows.get(session).map_err(db_error)? else {
                return Ok(false);
            };
            // A row it cannot read is not what it holds: the write replaces it.
            Ok(decrypt_blob(&self.dek, row.value()).is_ok_and(|held| held == expected))
        };
        Ok(holds(SESSIONS, record)? && holds(MLS_SNAPSHOT, snapshot)?)
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
            Self::update_row(tx, snapshots, id, Some(&snapshot))?;
            self.retire_accepted_offers(tx, records, id)
        })
    }
}
