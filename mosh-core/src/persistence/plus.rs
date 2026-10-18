use super::*;

impl Persistence {
    pub(crate) fn get_plus_record(&self, key: &str) -> Result<Option<Vec<u8>>, PersistenceError> {
        self.get(PLUS_RECORDS, key)
    }

    pub(crate) fn put_plus_record(&self, key: &str, record: &[u8]) -> Result<(), PersistenceError> {
        self.put(PLUS_RECORDS, key, record)
    }
}
