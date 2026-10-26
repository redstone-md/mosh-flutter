//! Stream bounded frozen deletion journals without cloning a source history.
use super::*;
use serde::de::DeserializeOwned;
use sha2::{Digest, Sha256};

impl Persistence {
    pub(crate) fn recovery_page<R: DeserializeOwned>(
        &self,
        prefix: &str,
        after: Option<&str>,
    ) -> Result<(Vec<R>, Option<String>), PersistenceError> {
        let tx = self.db.begin_read().map_err(db_error)?;
        let table = tx.open_table(CONVERSATION_RECOVERY).map_err(db_error)?;
        let start = after.map_or_else(|| prefix.to_owned(), |a| format!("{prefix}{a}"));
        let mut rows = Vec::new();
        let mut bytes = 0;
        let mut last = None;
        for row in table
            .range(start.as_str()..format!("{prefix}\u{10ffff}").as_str())
            .map_err(db_error)?
        {
            let (key, value) = row.map_err(db_error)?;
            if after.is_some_and(|after| key.value() == format!("{prefix}{after}")) {
                continue;
            }
            let raw = decrypt_blob(&self.dek, value.value())?;
            if rows.len() >= 16 || (!rows.is_empty() && bytes + raw.len() > 24_000) {
                return Ok((rows, last));
            }
            bytes += raw.len();
            rows.push(
                serde_json::from_slice(&raw).map_err(|e| PersistenceError::Json(e.to_string()))?,
            );
            last = key.value().strip_prefix(prefix).map(str::to_owned);
        }
        Ok((rows, None))
    }

    pub(crate) fn recovery_sequence_digest(
        &self,
        prefix: &str,
    ) -> Result<String, PersistenceError> {
        let tx = self.db.begin_read().map_err(db_error)?;
        let table = tx.open_table(CONVERSATION_RECOVERY).map_err(db_error)?;
        let mut digest = Sha256::new();
        digest.update(b"[");
        let mut first = true;
        for row in table
            .range(prefix..format!("{prefix}\u{10ffff}").as_str())
            .map_err(db_error)?
        {
            let (_, value) = row.map_err(db_error)?;
            if !first {
                digest.update(b",");
            }
            first = false;
            digest.update(decrypt_blob(&self.dek, value.value())?);
        }
        digest.update(b"]");
        Ok(hex::encode(digest.finalize()))
    }
}
