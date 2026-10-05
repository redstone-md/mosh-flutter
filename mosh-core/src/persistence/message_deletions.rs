use super::*;
use crate::{conversation::history::StoredMessage, message_deletion::DeletionRecord};

impl Persistence {
    pub(crate) fn account_deletions(
        &self,
        user: &str,
    ) -> Result<Vec<DeletionRecord>, PersistenceError> {
        self.list_rows(MESSAGE_DELETIONS)?
            .iter()
            .map(|(_, row)| {
                serde_json::from_slice::<DeletionRecord>(row)
                    .map_err(|e| PersistenceError::Json(e.to_string()))
            })
            .filter_map(|result| match result {
                Ok(record)
                    if (record.scope == crate::message_deletion::DeleteScope::ForMe
                        && record.owner == user
                        && !record.local_only)
                        || (record.scope == crate::message_deletion::DeleteScope::ForEveryone
                            && record.status
                                != crate::message_deletion::DeletionStatus::Rejected) =>
                {
                    Some(Ok(record))
                }
                Ok(_) => None,
                Err(error) => Some(Err(error)),
            })
            .collect()
    }

    pub(crate) fn save_account_deletions(
        &self,
        user: &str,
        records: &[DeletionRecord],
    ) -> Result<(), PersistenceError> {
        use crate::message_deletion::{DeleteScope, DeletionStatus};
        let mut rows = Vec::new();
        for record in records {
            if !["dm:", "group:", "channel:"]
                .iter()
                .any(|p| record.context.starts_with(p))
                || record.context.len() > 512
                || record.context.chars().any(char::is_control)
                || record.key.len() != 64
                || hex::decode(&record.key).is_err()
            {
                return Err(PersistenceError::Json("invalid deletion target".into()));
            }
            if record.scope == DeleteScope::ForEveryone {
                crate::message_deletion::shared::verify_record(record, &record.context)
                    .map_err(PersistenceError::Json)?;
                rows.push(record.clone());
                continue;
            }
            if record.owner != user
                || record.scope != DeleteScope::ForMe
                || record.local_only
                || record.status != DeletionStatus::Confirmed
                || record.request.is_some()
                || record.acknowledgement.is_some()
                || record.administrator.is_some()
            {
                return Err(PersistenceError::Json("invalid personal deletion".into()));
            }
            rows.push(record.clone());
        }
        self.write(|tx| {
            for record in &rows {
                self.merge_deletion_row(tx, record)?;
            }
            Ok(())
        })
    }
    pub(crate) fn deletion_records(
        &self,
        context: &str,
    ) -> Result<Vec<DeletionRecord>, PersistenceError> {
        self.range_prefix(MESSAGE_DELETIONS, context)?
            .iter()
            .map(|row| {
                serde_json::from_slice(row).map_err(|e| PersistenceError::Json(e.to_string()))
            })
            .collect()
    }

    /// The tombstones, empty history rows and cancellation of every matching
    /// outbound attempt commit together. Frozen history cursors retain their rows.
    pub(crate) fn commit_message_deletions<M: serde::Serialize>(
        &self,
        tables: HistoryTables,
        records: &[DeletionRecord],
        rows: &[&StoredMessage<M>],
        cancelled: &std::collections::HashSet<String>,
        attachments: &[crate::conversation::attachments::AttachmentDescriptor],
    ) -> Result<(), PersistenceError> {
        let messages = rows
            .iter()
            .map(|r| {
                Ok((
                    Self::history_message_key(&r.conversation_id, r.sent_at_ms, &r.message_id),
                    encrypt_blob(
                        &self.dek,
                        &serde_json::to_vec(r)
                            .map_err(|e| PersistenceError::Json(e.to_string()))?,
                    )?,
                    cancelled.contains(&r.message_id).then(|| {
                        Self::outbound_attempt_key(
                            tables.outbound_scope,
                            &r.conversation_id,
                            &r.message_id,
                        )
                    }),
                ))
            })
            .collect::<Result<Vec<_>, PersistenceError>>()?;
        self.write(|tx| {
            for attachment in attachments {
                self.enqueue_attachment_gc(tx, attachment)?;
            }
            for record in records {
                self.merge_deletion_row(tx, record)?;
            }
            for (key, value, attempt_key) in &messages {
                Self::update_row(tx, tables.messages, key, Some(value))?;
                if let Some(attempt_key) = attempt_key {
                    Self::update_row(tx, OUTBOUND_ATTEMPTS, attempt_key, None)?;
                }
            }
            Ok(())
        })
    }
}
