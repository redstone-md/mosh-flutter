//! Ordered group commit evidence retained for resynchronization.
use super::*;

impl Persistence {
    fn commit_log_key(group_id: &str, epoch: u64) -> String {
        format!("{group_id}/{epoch:020}")
    }

    pub fn append_group_commit(
        &self,
        group_id: &str,
        epoch: u64,
        commit: &[u8],
    ) -> Result<(), PersistenceError> {
        // '/' is the key separator; a group_id containing it would collide
        // with a sibling group's key space and poison its resync range.
        // group_ids can arrive in remote offers, so fail closed.
        if group_id.contains('/') {
            return Err(PersistenceError::Db(format!(
                "group_id must not contain '/': {group_id}"
            )));
        }
        self.put(
            GROUP_COMMIT_LOG,
            &Self::commit_log_key(group_id, epoch),
            commit,
        )
    }

    pub fn list_group_commits_from(
        &self,
        group_id: &str,
        from_epoch: u64,
    ) -> Result<Vec<(u64, Vec<u8>)>, PersistenceError> {
        let rtx = self.db.begin_read().map_err(db_error)?;
        let table = rtx.open_table(GROUP_COMMIT_LOG).map_err(db_error)?;
        let start = Self::commit_log_key(group_id, from_epoch);
        let end = format!("{group_id}/{}", "9".repeat(21)); // beyond any 20-digit epoch
        let prefix = format!("{group_id}/");
        let mut out = Vec::new();
        for entry in table
            .range(start.as_str()..end.as_str())
            .map_err(db_error)?
        {
            let (key, value) = entry.map_err(db_error)?;
            let key = key.value();
            let Some(epoch_str) = key.strip_prefix(&prefix) else {
                continue;
            };
            // Skip foreign/malformed keys instead of failing the whole read:
            // one bad key must not DoS a group's resync.
            if epoch_str.len() != 20 || !epoch_str.bytes().all(|b| b.is_ascii_digit()) {
                continue;
            }
            let Ok(epoch) = epoch_str.parse::<u64>() else {
                continue;
            };
            out.push((epoch, decrypt_blob(&self.dek, value.value())?));
        }
        Ok(out)
    }
}
