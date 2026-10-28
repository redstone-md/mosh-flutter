//! Shared atomic admission installs rows, original evidence and continuation together.
use super::records::GroupRecord;
use super::*;
use crate::conversation::recovery::{
    coordinator::Checkpoint, manifest::HistoryKey, occurrence::Occurrence,
};
use crate::persistence::history_admission::EvidenceWrite;

impl GroupSession {
    pub(super) fn save_history(
        &mut self,
        mut next: Checkpoint,
        rows: &[StoredMessage<GroupMessage>],
        evidence: &[EvidenceWrite],
        receipts: &[EvidenceWrite],
    ) -> Result<(), PrivateGroupError> {
        let head = self.current_history_head()?;
        let store = self
            .persistence
            .clone()
            .ok_or(PrivateGroupError::NotReady)?;
        let occurrences = rows
            .iter()
            .map(|row| GroupRecord::occurrence(row, &self.deletions.context, &self.mesh_id))
            .collect::<Result<Vec<_>, _>>()
            .map_err(PrivateGroupError::Codec)?
            .into_iter()
            .flatten()
            .collect::<Vec<_>>();
        let preparing = !self.recovery.occurrences_ready;
        let completed_source = self.recovery.checkpoint.source.is_some()
            && next.source.is_none()
            && next.progress.complete;
        if preparing || completed_source {
            let incomplete = std::cell::Cell::new(false);
            store.prepare_history_occurrences(GROUP_HISTORY, &self.group_id, |row| {
                let (occurrence, lost_preview) = self.retained_history_occurrence(row)?;
                let repairing = occurrence.as_ref().is_some_and(|o| occurrences.contains(o));
                incomplete.set(incomplete.get() || (lost_preview && !repairing));
                Ok(occurrence)
            })?;
            if incomplete.get() {
                // The same original manifest must be requested again, not
                // treated as complete because it was observed before damage.
                if preparing {
                    next.observed.clear();
                }
                next.progress.complete = false;
            }
        }
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
        self.recovery.occurrences_ready = true;
        if !rows.is_empty() {
            // Repair can change only a retained preview, leaving the visible
            // message count and descriptor unchanged.
            self.history_exports = Default::default();
        }
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

    fn retained_history_occurrence(
        &self,
        row: &StoredMessage<GroupMessage>,
    ) -> Result<(Option<Occurrence>, bool), String> {
        let current = GroupRecord::occurrence(row, &self.deletions.context, &self.mesh_id)?;
        let Some(current) = current else {
            return Ok((None, false));
        };
        if row.attachment_manifest.is_none()
            || row.preview_manifest.is_some()
            || current.content_digest.is_none()
        {
            return Ok((Some(current), false));
        }
        let store = self
            .persistence
            .as_ref()
            .ok_or("group persistence unavailable")?;
        let retained = store
            .history_occurrence(GROUP_HISTORY, &self.group_id, &row.message_id)
            .map_err(|e| e.to_string())?;
        let Some(retained) = retained.filter(|old| {
            old.native_id == current.native_id
                && old.row_key == current.row_key
                && old.identity == current.identity
                && old.content_digest.is_some()
                && old.content_digest != current.content_digest
        }) else {
            return Ok((Some(current), false));
        };
        self.verify_retained_occurrence(&row.message_id, &retained)?;
        Ok((Some(retained), true))
    }

    fn verify_retained_occurrence(&self, id: &str, retained: &Occurrence) -> Result<(), String> {
        let store = self
            .persistence
            .as_ref()
            .ok_or("group persistence unavailable")?;
        let accepted: NativeAcceptance = store
            .group_history_evidence(&native_acceptance_key(&self.group_id, id))
            .map_err(|e| e.to_string())?
            .ok_or("protected group acceptance unavailable")?;
        accepted
            .receipt
            .as_ref()
            .ok_or("protected group receipt unavailable")?
            .verify(&accepted)
            .map_err(|e| e.to_string())?;
        if retained.content_digest.as_ref() != Some(&accepted.record_hash)
            || accepted
                .origin
                .as_ref()
                .map(|o| o.key())
                .transpose()?
                .as_ref()
                != Some(&retained.identity)
        {
            return Err("protected group occurrence differs".into());
        }
        Ok(())
    }
}
