//! One native admission transaction for live and imported conversation history.
use super::*;
use crate::conversation::{history::StoredMessage, recovery::occurrence::Occurrence};

/// Values are serialized typed evidence owned and verified by the kind adapter.
pub(crate) struct EvidenceWrite {
    pub key: String,
    pub bytes: Vec<u8>,
}

pub(crate) struct OrgAuthorityGuard<'a> {
    pub org_key: &'a str,
    pub roster_bytes: &'a [u8],
}

pub(crate) struct GroupHeadGuard<'a> {
    pub key: &'a str,
    pub expected: Option<&'a [u8]>,
}

#[derive(Default)]
pub(crate) struct HistoryAdmission<'a> {
    pub org_authority: Option<OrgAuthorityGuard<'a>>,
    pub group_head: Option<GroupHeadGuard<'a>>,
    pub state: Option<(&'a str, &'a [u8])>,
    pub checkpoint: Option<(&'a str, &'a [u8])>,
    /// The receiving installation's staged snapshot; never another holder's state.
    pub own_snapshot: Option<&'a [u8]>,
    /// Welcome acceptance retains the existing organization-offer retirement.
    pub finalize_native: bool,
    pub recovery: &'a [EvidenceWrite],
    pub evidence: &'a [EvidenceWrite],
    pub occurrences: &'a [Occurrence],
    /// Complete namespace; the shared prefix eraser adds the delimiter itself.
    pub remove_recovery_prefix: Option<&'a str>,
}

impl HistoryAdmission<'_> {
    fn writes<'a>(
        &'a self,
        tables: HistoryTables,
        id: &'a str,
    ) -> Result<Vec<(Rows, &'a str, &'a [u8])>, PersistenceError> {
        let mut writes = Vec::new();
        if let Some((key, bytes)) = self.state {
            writes.push((tables.conversations, key, bytes));
        }
        if let Some((key, bytes)) = self.checkpoint {
            writes.push((CONVERSATION_RECOVERY, key, bytes));
        }
        if let Some(bytes) = self.own_snapshot {
            let table = tables
                .snapshots
                .ok_or_else(|| PersistenceError::Json("history kind has no MLS snapshot".into()))?;
            writes.push((table, id, bytes));
        }
        for value in self.recovery {
            writes.push((
                CONVERSATION_RECOVERY,
                value.key.as_str(),
                value.bytes.as_slice(),
            ));
        }
        for evidence in self.evidence {
            writes.push((
                GROUP_HISTORY_EVIDENCE,
                evidence.key.as_str(),
                evidence.bytes.as_slice(),
            ));
        }
        Ok(writes)
    }
}

impl Persistence {
    pub(crate) fn commit_history_admission<M: serde::Serialize>(
        &self,
        tables: HistoryTables,
        id: &str,
        admission: HistoryAdmission<'_>,
        messages: &[StoredMessage<M>],
    ) -> Result<(), PersistenceError> {
        let writes = admission
            .writes(tables, id)?
            .into_iter()
            .map(|(table, key, bytes)| {
                encrypt_blob(&self.dek, bytes).map(|value| (table, key, value))
            })
            .collect::<Result<Vec<_>, _>>()?;
        let rows = self.prepare_history_rows(id, messages)?;
        self.write(|tx| {
            self.check_history_authority(tx, &admission)?;
            for occurrence in admission.occurrences {
                self.admit_occurrence(tx, tables, id, occurrence)?;
            }
            for (key, value) in &rows {
                self.write_history_row(tx, tables, key, value)?;
            }
            for (table, key, value) in &writes {
                Self::update_row(tx, *table, key, Some(value))?;
            }
            if admission.finalize_native {
                self.retire_accepted_offers(tx, tables.conversations, id)?;
            }
            if let Some(prefix) = admission.remove_recovery_prefix {
                self.delete_prefix(tx, CONVERSATION_RECOVERY, prefix)?;
            }
            Ok(())
        })
    }

    fn prepare_history_rows<M: serde::Serialize>(
        &self,
        id: &str,
        messages: &[StoredMessage<M>],
    ) -> Result<Vec<(String, Vec<u8>)>, PersistenceError> {
        messages
            .iter()
            .map(|message| {
                let bytes = serde_json::to_vec(message)
                    .map_err(|e| PersistenceError::Json(e.to_string()))?;
                Ok((
                    Self::history_message_key(id, message.sent_at_ms, &message.message_id),
                    encrypt_blob(&self.dek, &bytes)?,
                ))
            })
            .collect()
    }

    fn check_history_authority(
        &self,
        tx: &redb::WriteTransaction,
        admission: &HistoryAdmission<'_>,
    ) -> Result<(), PersistenceError> {
        if let Some(guard) = &admission.org_authority {
            if self
                .read_transaction_blob(tx, ORG_ROSTERS, guard.org_key)?
                .as_deref()
                != Some(guard.roster_bytes)
            {
                return Err(PersistenceError::Json(
                    "history organization authority changed".into(),
                ));
            }
        }
        if let Some(guard) = &admission.group_head {
            if self
                .read_transaction_blob(tx, GROUP_HISTORY_EVIDENCE, guard.key)?
                .as_deref()
                != guard.expected
            {
                return Err(PersistenceError::Json(
                    "history membership head changed".into(),
                ));
            }
        }
        Ok(())
    }
}
