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
            HistoryMessage::Pull {
                manifest,
                offset,
                fragment_offset,
                deletion_digest,
                journal,
                journal_after,
            } => {
                self.serve_history(
                    &frame,
                    manifest,
                    offset,
                    fragment_offset,
                    deletion_digest,
                    journal,
                    journal_after,
                )?;
            }
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
                self.recovery.last_progress = 0;
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
        let current = &self.recovery.checkpoint;
        if frame.round != current.round
            || frame.request_id != current.progress.request_id
            || current.source.is_some()
            || current.observed.get(&frame.sender_key) == Some(&manifest)
            || manifest.len() != 64
            || hex::decode(&manifest).is_err()
            || deletion_digest.len() != 64
            || hex::decode(&deletion_digest).is_err()
        {
            return Ok(());
        }
        let mut next = current.clone();
        next.source = Some(frame.sender_key.clone());
        next.progress.manifest = Some(manifest);
        next.progress.total = Some(total);
        next.progress.complete = false;
        next.deletion_digest = deletion_digest;
        next.journal_after = None;
        next.journal_complete = false;
        self.save_checkpoint(next, &[])?;
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
            HistoryMessage::Pull {
                manifest: checkpoint.progress.manifest.clone().unwrap_or_default(),
                offset: checkpoint.progress.cursor,
                fragment_offset: checkpoint.partial.as_ref().map_or(0, |p| p.offset()),
                deletion_digest: checkpoint.deletion_digest.clone(),
                journal: !checkpoint.journal_complete,
                journal_after: checkpoint.journal_after.clone(),
            },
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
        } else if next.partial.is_some() {
            return Err(ChannelRuntimeError::Codec(
                "history partial record missing".into(),
            ));
        }
        let mut rows = Vec::new();
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
            if let Some(existing) = self
                .messages
                .iter()
                .find(|m| m.message_id.as_ref() == Some(&record.message_id))
            {
                if existing
                    .metadata
                    .as_ref()
                    .is_none_or(|m| m.deletion.is_none())
                    && (existing.body != record.body()
                        || existing.from_fingerprint != record.from_fingerprint
                        || existing.sent_at_ms != Some(record.sent_at_ms))
                {
                    return Err(ChannelRuntimeError::Codec(
                        "conflicting history occurrence".into(),
                    ));
                }
            }
            let classification = if record.origin.is_some() {
                crate::conversation::recovery::HistoryClassification::OriginalOrigin
            } else {
                crate::conversation::recovery::HistoryClassification::LegacyUnsigned
            };
            let mut row = record.row(&self.name);
            row.history_evidence = Some(crate::conversation::recovery::HistoryEvidence {
                holder_key: frame.sender_key.clone(),
                classification,
            });
            rows.push(row);
        }
        next.progress
            .advance(&manifest, total, rows.len(), next.partial.is_some())
            .map_err(ChannelRuntimeError::Codec)?;
        if next.progress.complete {
            if next.observed.len() >= 16 {
                next.observed.pop_first();
            }
            next.observed.insert(frame.sender_key.clone(), manifest);
            next.source = None;
        }
        self.save_checkpoint(next, &rows)?;
        self.recovery.last_progress = crate::conversation::now_ms();
        self.pull_history(self.recovery.last_progress)
    }

    pub(super) fn save_checkpoint(
        &mut self,
        next: Checkpoint,
        rows: &[StoredMessage<ChannelMessage>],
    ) -> Result<(), ChannelRuntimeError> {
        let store =
            self.deletions.store.as_ref().ok_or_else(|| {
                ChannelRuntimeError::Persistence("history store unavailable".into())
            })?;
        store.prepare_history_occurrences(
            CHANNEL_HISTORY,
            &self.name,
            ChannelRecord::occurrence,
        )?;
        let occurrences = rows
            .iter()
            .map(ChannelRecord::occurrence)
            .collect::<Result<Vec<_>, _>>()
            .map_err(ChannelRuntimeError::Codec)?
            .into_iter()
            .flatten()
            .collect::<Vec<_>>();
        store.commit_history_recovery(
            CHANNEL_HISTORY,
            &self.name,
            &self.checkpoint_key(),
            &next,
            rows,
            &occurrences,
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
                if !self.messages.holds_copy_of(&saved.message) {
                    self.messages.upsert(saved.message);
                }
            }
        }
        self.recovery.checkpoint = next;
        self.recovery.error = None;
        Ok(())
    }
}
