//! Install accepted rows and cursor together, then expose only the stored sanitized result.
use super::*;
use crate::conversation::{history::StoredMessage, recovery::manifest::HistoryKey};

impl ChannelSession {
    pub(super) fn save_checkpoint(
        &mut self,
        next: Checkpoint,
        rows: &[StoredMessage<ChannelMessage>],
    ) -> Result<(), ChannelRuntimeError> {
        self.save_history_rows(next, rows, &[])
    }

    pub(super) fn save_history_rows(
        &mut self,
        next: Checkpoint,
        rows: &[StoredMessage<ChannelMessage>],
        receipts: &[crate::persistence::history_admission::EvidenceWrite],
    ) -> Result<(), ChannelRuntimeError> {
        self.prepare_history_index()?;
        let store = self.deletions.store.as_ref().unwrap();
        let occurrences = rows
            .iter()
            .map(ChannelRecord::occurrence)
            .collect::<Result<Vec<_>, _>>()
            .map_err(ChannelRuntimeError::Codec)?
            .into_iter()
            .flatten()
            .collect::<Vec<_>>();
        let key = self.checkpoint_key();
        let bytes =
            serde_json::to_vec(&next).map_err(|e| ChannelRuntimeError::Codec(e.to_string()))?;
        let cleanup = (next.progress.request_id != self.recovery.checkpoint.progress.request_id)
            .then(|| {
                format!(
                    "{key}\u{1}request\u{1}{}",
                    self.recovery.checkpoint.progress.request_id
                )
            });
        store.commit_history_admission(
            CHANNEL_HISTORY,
            &self.name,
            crate::persistence::HistoryAdmission {
                checkpoint: Some((&key, &bytes)),
                occurrences: &occurrences,
                recovery: receipts,
                remove_recovery_prefix: cleanup.as_deref(),
                ..Default::default()
            },
            rows,
        )?;
        self.restore_history_rows(rows)?;
        self.recovery.installed(next);
        Ok(())
    }
    fn prepare_history_index(&mut self) -> Result<(), ChannelRuntimeError> {
        let store =
            self.deletions.store.as_ref().ok_or_else(|| {
                ChannelRuntimeError::Persistence("history store unavailable".into())
            })?;
        if !self.recovery.occurrences_ready {
            store.prepare_history_occurrences(
                CHANNEL_HISTORY,
                &self.name,
                ChannelRecord::occurrence,
            )?;
            self.recovery.occurrences_ready = true;
        }
        Ok(())
    }

    fn restore_history_rows(
        &mut self,
        rows: &[StoredMessage<ChannelMessage>],
    ) -> Result<(), ChannelRuntimeError> {
        let store = self.deletions.store.as_ref().unwrap();
        for row in rows {
            let key = HistoryKey {
                message_id: row.message_id.clone(),
                sent_at_ms: row.sent_at_ms,
                digest: String::new(),
            };
            if let Some(saved) =
                store.history_message::<ChannelMessage>(CHANNEL_HISTORY, &self.name, &key)?
            {
                if let Some(descriptor) = &saved.message.attachment {
                    if saved
                        .message
                        .metadata
                        .as_ref()
                        .is_none_or(|m| m.deletion.is_none())
                    {
                        self.transfer.restore_stored(
                            descriptor,
                            crate::conversation::attachments::AttachmentDirection::Incoming,
                            saved.attachment_manifest.clone(),
                        );
                    }
                }
                if saved
                    .message
                    .metadata
                    .as_ref()
                    .is_some_and(|m| m.deletion.is_some())
                    || !self.messages.holds_copy_of(&saved.message)
                {
                    self.messages.upsert(saved.message);
                }
            }
        }
        Ok(())
    }
}
