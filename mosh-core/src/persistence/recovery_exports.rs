//! Export reservations are bounded and expire in the same transaction as keys.
use super::*;
use serde::Deserialize;

#[derive(Deserialize)]
struct Lease {
    expires_ms: u64,
}

impl Persistence {
    pub(super) fn reserve_recovery_export(
        &self,
        tx: &redb::WriteTransaction,
        meta_key: &str,
        data_prefix: &str,
        now: u64,
    ) -> Result<(), PersistenceError> {
        let (meta_prefix, recipient) = meta_key
            .rsplit_once('\u{1}')
            .ok_or_else(|| PersistenceError::Json("invalid recovery export key".into()))?;
        let data_base = data_prefix
            .strip_suffix(recipient)
            .ok_or_else(|| PersistenceError::Json("invalid recovery export data prefix".into()))?;
        let meta_prefix = format!("{meta_prefix}\u{1}");
        let mut stale = Vec::new();
        let mut active = 0;
        {
            let table = tx.open_table(CONVERSATION_RECOVERY).map_err(db_error)?;
            for row in table
                .range(meta_prefix.as_str()..format!("{meta_prefix}\u{10ffff}").as_str())
                .map_err(db_error)?
            {
                let (key, value) = row.map_err(db_error)?;
                let lease: Lease = serde_json::from_slice(&decrypt_blob(&self.dek, value.value())?)
                    .map_err(|e| PersistenceError::Json(e.to_string()))?;
                if lease.expires_ms <= now {
                    stale.push(key.value().to_owned());
                } else if key.value() != meta_key {
                    active += 1;
                }
            }
        }
        if active >= 16 {
            return Err(PersistenceError::Json(
                "recovery export capacity reached".into(),
            ));
        }
        for key in stale {
            let recipient = key.strip_prefix(&meta_prefix).unwrap_or_default();
            self.delete_prefix(
                tx,
                CONVERSATION_RECOVERY,
                &format!("{data_base}{recipient}"),
            )?;
            Self::update_row(tx, CONVERSATION_RECOVERY, &key, None)?;
        }
        Ok(())
    }
}
