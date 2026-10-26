use super::*;
use crate::conversation::history::StoredMessage;
use crate::conversation::recovery::manifest::HistoryKey;

impl ChannelSession {
    pub(super) fn receive_history(
        &mut self,
        frame: HistoryFrame,
    ) -> Result<bool, ChannelRuntimeError> {
        let message = frame
            .open(&self.deletions.context, &self.mesh_id, &self.blob_topic)
            .map_err(ChannelRuntimeError::Codec)?;
        match message {
            HistoryMessage::Probe => {
                let manifest = self.history_manifest()?;
                self.reply_history(
                    Some(frame.sender_key),
                    frame.request_id,
                    frame.round,
                    HistoryMessage::Offer {
                        manifest: manifest.digest,
                        total: manifest.total,
                        deletion_digest: self.history_deletion_digest()?,
                    },
                )?;
            }
            HistoryMessage::Pull(pull) => self.serve_history(&frame, pull)?,
            HistoryMessage::Offer {
                manifest,
                total,
                deletion_digest,
            } => {
                self.select_history(&frame, manifest, total, deletion_digest)?;
            }
            HistoryMessage::Journal {
                manifest,
                deletion_digest,
                page,
            } => {
                self.import_history_journal(&frame, manifest, deletion_digest, page)?;
            }
            HistoryMessage::Page {
                manifest,
                total,
                offset,
                records,
                fragment,
            } => {
                self.import_history(&frame, manifest, total, offset, records, fragment)?;
                return Ok(true);
            }
            HistoryMessage::Unavailable => {
                self.recovery
                    .unavailable(&frame, crate::conversation::now_ms());
            }
        }
        Ok(false)
    }

    fn select_history(
        &mut self,
        frame: &HistoryFrame,
        manifest: String,
        total: usize,
        deletion_digest: String,
    ) -> Result<(), ChannelRuntimeError> {
        let Some((next, permit)) = self
            .recovery
            .offered(
                frame,
                manifest,
                total,
                deletion_digest,
                &self.device_fingerprint,
                &self.deletions.context,
            )
            .map_err(ChannelRuntimeError::Codec)?
        else {
            return Ok(());
        };
        self.save_checkpoint(next, &[])?;
        self.recovery.permit = Some(permit);
        self.recovery.last_progress = crate::conversation::now_ms();
        self.pull_history(self.recovery.last_progress)
    }

    pub(super) fn pull_history(&mut self, now: u64) -> Result<(), ChannelRuntimeError> {
        let checkpoint = &self.recovery.checkpoint;
        let Some(source) = checkpoint.source.clone() else {
            return Ok(());
        };
        self.send_history(
            Some(source),
            HistoryMessage::Pull(HistoryPull {
                manifest: checkpoint.progress.manifest.clone().unwrap_or_default(),
                offset: checkpoint.progress.cursor,
                fragment_offset: checkpoint.partial.as_ref().map_or(0, |p| p.offset()),
                deletion_digest: checkpoint.deletion_digest.clone(),
                journal: !checkpoint.journal_complete,
                journal_after: checkpoint.journal_after.clone(),
            }),
        )?;
        self.recovery.last_pull = now;
        Ok(())
    }

    fn import_history(
        &mut self,
        frame: &HistoryFrame,
        manifest: String,
        total: usize,
        offset: usize,
        mut records: Vec<ChannelRecord>,
        fragment: Option<crate::conversation::recovery::fragment::PageFragment>,
    ) -> Result<(), ChannelRuntimeError> {
        let mut next = self.recovery.checkpoint.clone();
        if next.round != frame.round
            || next.source.as_ref() != Some(&frame.sender_key)
            || next.progress.request_id != frame.request_id
            || !next.journal_complete
        {
            return Ok(());
        }
        next.progress
            .check(&frame.request_id, offset, &manifest, total, records.len())
            .map_err(ChannelRuntimeError::Codec)?;
        if let Some(fragment) = fragment {
            if !records.is_empty() {
                return Err(ChannelRuntimeError::Codec("mixed history fragment".into()));
            }
            if let Some(bytes) = crate::conversation::recovery::fragment::PartialRecord::accept(
                &mut next.partial,
                fragment,
            )
            .map_err(ChannelRuntimeError::Codec)?
            {
                records.push(
                    serde_json::from_slice(&bytes)
                        .map_err(|e| ChannelRuntimeError::Codec(e.to_string()))?,
                );
            }
        } else if next.partial.is_some()
            && records.len() == 1
            && matches!(records[0].content, records::Content::Erased { .. })
        {
            next.partial = None;
        } else if next.partial.is_some() {
            return Err(ChannelRuntimeError::Codec(
                "history partial record missing".into(),
            ));
        }
        let mut rows = Vec::new();
        let mut receipts = Vec::new();
        let mut ids = std::collections::HashSet::new();
        for record in records {
            record
                .validate(&self.deletions.context)
                .map_err(ChannelRuntimeError::Codec)?;
            if !ids.insert(record.message_id.clone()) {
                return Err(ChannelRuntimeError::Codec(
                    "duplicate history occurrence".into(),
                ));
            }
            receipts.push(HistoryKey {
                message_id: record.message_id.clone(),
                sent_at_ms: record.sent_at_ms,
                digest: record
                    .binding_digest()
                    .map_err(ChannelRuntimeError::Codec)?,
            });
            rows.push(self.history_row_for(record, &frame.sender_key)?);
        }
        next.progress
            .advance(&manifest, total, rows.len(), next.partial.is_some())
            .map_err(ChannelRuntimeError::Codec)?;
        let prefix = format!(
            "{}\u{1}request\u{1}{}\u{1}receipts\u{1}",
            self.checkpoint_key(),
            frame.request_id
        );
        if next.progress.complete
            && self
                .deletions
                .store
                .as_ref()
                .unwrap()
                .recovery_digest_with_tail(&prefix, Some(&self.deletions.context), &receipts)?
                != manifest
        {
            return Err(ChannelRuntimeError::Codec(
                "history frozen manifest differs".into(),
            ));
        }
        let receipts = receipts
            .iter()
            .enumerate()
            .map(|(index, key)| {
                Ok(crate::persistence::history_admission::EvidenceWrite {
                    key: format!("{prefix}{:020}", offset + index),
                    bytes: serde_json::to_vec(key)
                        .map_err(|e| ChannelRuntimeError::Codec(e.to_string()))?,
                })
            })
            .collect::<Result<Vec<_>, ChannelRuntimeError>>()?;
        Recovery::finished(&mut next, &frame.sender_key);
        self.save_history_rows(next, &rows, &receipts)?;
        self.recovery.last_progress = crate::conversation::now_ms();
        self.pull_history(self.recovery.last_progress)
    }

    pub(super) fn save_checkpoint(
        &mut self,
        next: Checkpoint,
        rows: &[StoredMessage<ChannelMessage>],
    ) -> Result<(), ChannelRuntimeError> {
        self.save_history_rows(next, rows, &[])
    }

    fn save_history_rows(
        &mut self,
        next: Checkpoint,
        rows: &[StoredMessage<ChannelMessage>],
        receipts: &[crate::persistence::history_admission::EvidenceWrite],
    ) -> Result<(), ChannelRuntimeError> {
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
                    "{key}\u{1}request\u{1}{}\u{1}",
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
        self.recovery.installed(next);
        Ok(())
    }
}
