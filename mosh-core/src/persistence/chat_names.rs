//! Account-scoped personal names share the encrypted row boundary.
use super::*;

impl Persistence {
    pub(crate) fn get_chat_names(&self, user: &str) -> Result<Option<Vec<u8>>, PersistenceError> {
        self.get(CHAT_NAMES, user)
    }

    pub(crate) fn put_chat_names(&self, user: &str, record: &[u8]) -> Result<(), PersistenceError> {
        self.put(CHAT_NAMES, user, record)
    }
}
