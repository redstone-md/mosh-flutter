use super::*;
use std::collections::BTreeSet;

impl Persistence {
    /// This table is written only by native admission, never account-history import.
    pub(crate) fn accepted_deletions(
        &self,
        context: &str,
    ) -> Result<BTreeSet<String>, PersistenceError> {
        self.range_prefix(DELETION_ACCEPTANCE, context)?
            .iter()
            .map(|row| {
                serde_json::from_slice::<crate::message_deletion::protocol::DeleteAck>(row)
                    .map(|ack| ack.request_digest)
                    .map_err(|e| PersistenceError::Json(e.to_string()))
            })
            .collect()
    }

    pub(super) fn save_deletion_acceptance(
        &self,
        tx: &redb::WriteTransaction,
        record: &crate::message_deletion::DeletionRecord,
    ) -> Result<(), PersistenceError> {
        if record.status != crate::message_deletion::DeletionStatus::Confirmed
            || record.acknowledgement.is_none()
        {
            return Ok(());
        }
        let Some(request) = &record.request else {
            return Ok(());
        };
        let digest = request.digest().map_err(PersistenceError::Json)?;
        let key = format!("{}\u{0001}{}", record.context, digest);
        let bytes = serde_json::to_vec(record.acknowledgement.as_ref().unwrap())
            .map_err(|e| PersistenceError::Json(e.to_string()))?;
        Self::update_row(
            tx,
            DELETION_ACCEPTANCE,
            &key,
            Some(&encrypt_blob(&self.dek, &bytes)?),
        )
    }
}
