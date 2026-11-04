//! Encrypted read marks, one row per conversation.
use super::*;

impl Persistence {
    pub(super) fn read_mark_key(tables: HistoryTables, id: &str) -> String {
        format!("{}:{id}", tables.label)
    }

    pub(crate) fn get_read_mark(
        &self,
        tables: HistoryTables,
        id: &str,
    ) -> Result<Option<Vec<u8>>, PersistenceError> {
        self.get(READ_MARKS, &Self::read_mark_key(tables, id))
    }

    pub(crate) fn put_read_mark(
        &self,
        tables: HistoryTables,
        id: &str,
        mark: &[u8],
    ) -> Result<(), PersistenceError> {
        self.put(READ_MARKS, &Self::read_mark_key(tables, id), mark)
    }
}
