//! One native admission transaction for live and imported conversation history.
use super::*;
use crate::conversation::{history::StoredMessage, recovery::occurrence::Occurrence};

/// Values are serialized typed evidence owned and verified by the kind adapter.
pub(crate) struct EvidenceWrite {
    pub key: String,
    pub bytes: Vec<u8>,
}

#[derive(Default)]
pub(crate) struct HistoryAdmission<'a> {
    pub state: Option<(&'a str, &'a [u8])>,
    pub checkpoint: Option<(&'a str, &'a [u8])>,
    /// The receiving installation's staged snapshot; never another holder's state.
    pub own_snapshot: Option<&'a [u8]>,
    pub evidence: &'a [EvidenceWrite],
    pub occurrences: &'a [Occurrence],
    pub remove_recovery_prefix: Option<&'a str>,
}

impl Persistence {
    pub(crate) fn commit_history_admission<M: serde::Serialize>(
        &self,
        tables: HistoryTables,
        id: &str,
        admission: HistoryAdmission<'_>,
        messages: &[StoredMessage<M>],
    ) -> Result<(), PersistenceError> {
        let mut writes = Vec::new();
        if let Some((key, bytes)) = admission.state {
            writes.push((tables.conversations, key, bytes));
        }
        if let Some((key, bytes)) = admission.checkpoint {
            writes.push((CONVERSATION_RECOVERY, key, bytes));
        }
        if let Some(bytes) = admission.own_snapshot {
            let table = tables
                .snapshots
                .ok_or_else(|| PersistenceError::Json("history kind has no MLS snapshot".into()))?;
            writes.push((table, id, bytes));
        }
        for evidence in admission.evidence {
            writes.push((
                GROUP_HISTORY_EVIDENCE,
                evidence.key.as_str(),
                evidence.bytes.as_slice(),
            ));
        }
        let writes = writes
            .into_iter()
            .map(|(table, key, bytes)| {
                encrypt_blob(&self.dek, bytes).map(|value| (table, key, value))
            })
            .collect::<Result<Vec<_>, _>>()?;
        let rows = messages
            .iter()
            .map(|message| {
                let bytes = serde_json::to_vec(message)
                    .map_err(|e| PersistenceError::Json(e.to_string()))?;
                Ok((
                    Self::history_message_key(id, message.sent_at_ms, &message.message_id),
                    encrypt_blob(&self.dek, &bytes)?,
                ))
            })
            .collect::<Result<Vec<_>, PersistenceError>>()?;
        self.write(|tx| {
            for occurrence in admission.occurrences {
                self.admit_occurrence(tx, tables, id, occurrence)?;
            }
            for (key, value) in &rows {
                self.write_history_row(tx, tables, key, value)?;
            }
            for (table, key, value) in &writes {
                Self::update_row(tx, *table, key, Some(value))?;
            }
            if let Some(prefix) = admission.remove_recovery_prefix {
                self.delete_prefix(tx, CONVERSATION_RECOVERY, prefix)?;
            }
            Ok(())
        })
    }
}
