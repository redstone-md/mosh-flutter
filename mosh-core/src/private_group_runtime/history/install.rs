//! Shared atomic admission installs rows, original evidence and continuation together.
use super::records::GroupRecord;
use super::*;
use crate::conversation::recovery::{coordinator::Checkpoint, manifest::HistoryKey};
use crate::persistence::history_admission::EvidenceWrite;

impl GroupSession {
    pub(super) fn save_history(
        &mut self,
        next: Checkpoint,
        rows: &[StoredMessage<GroupMessage>],
        evidence: &[EvidenceWrite],
        receipts: &[EvidenceWrite],
    ) -> Result<(), PrivateGroupError> {
        let head = self.current_history_head()?;
        let store = self
            .persistence
            .clone()
            .ok_or(PrivateGroupError::NotReady)?;
        if !self.recovery.occurrences_ready {
            store.prepare_history_occurrences(GROUP_HISTORY, &self.group_id, |row| {
                GroupRecord::occurrence(row, &self.deletions.context, &self.mesh_id)
            })?;
            self.recovery.occurrences_ready = true;
        }
        let occurrences = rows
            .iter()
            .map(|row| GroupRecord::occurrence(row, &self.deletions.context, &self.mesh_id))
            .collect::<Result<Vec<_>, _>>()
            .map_err(PrivateGroupError::Codec)?
            .into_iter()
            .flatten()
            .collect::<Vec<_>>();
        let key = self.checkpoint_key();
        let bytes = serde_json::to_vec(&super::recovery::GroupCheckpoint {
            checkpoint: next.clone(),
            head,
        })
        .map_err(|e| PrivateGroupError::Codec(e.to_string()))?;
        let cleanup = (next.progress.request_id != self.recovery.checkpoint.progress.request_id)
            .then(|| {
                format!(
                    "{key}\u{1}request\u{1}{}",
                    self.recovery.checkpoint.progress.request_id
                )
            });
        let background = rows
            .iter()
            .filter_map(|row| {
                crate::conversation::history::background::message(
                    GROUP_HISTORY,
                    &self.group_id,
                    row.sent_at_ms,
                    &row.message_id,
                    &row.message,
                )
            })
            .collect::<Vec<_>>();
        store.commit_history_admission(
            GROUP_HISTORY,
            &self.group_id,
            HistoryAdmission {
                org_authority: self.org_history_guard(&self.device_fingerprint.clone(), false)?,
                checkpoint: Some((&key, &bytes)),
                occurrences: &occurrences,
                evidence,
                recovery: receipts,
                background_messages: &background,
                remove_recovery_prefix: cleanup.as_deref(),
                ..Default::default()
            },
            rows,
        )?;
        for row in rows {
            let key = HistoryKey {
                message_id: row.message_id.clone(),
                sent_at_ms: row.sent_at_ms,
                digest: String::new(),
            };
            if let Some(saved) =
                store.history_message::<GroupMessage>(GROUP_HISTORY, &self.group_id, &key)?
            {
                if !self.messages.holds_copy_of(&saved.message) {
                    self.restore_history_offer(&saved);
                    self.messages.upsert(saved.message);
                }
            }
        }
        self.recovery.installed(next);
        Ok(())
    }
}
