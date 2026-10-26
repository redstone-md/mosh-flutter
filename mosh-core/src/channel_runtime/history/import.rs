//! Verify a source page completely before advancing its durable continuation.
use super::*;
use crate::conversation::{
    history::StoredMessage,
    recovery::{
        fragment::{PageFragment, PartialRecord},
        manifest::HistoryKey,
    },
};
use crate::persistence::history_admission::EvidenceWrite;

impl ChannelSession {
    pub(super) fn import_history(
        &mut self,
        frame: &HistoryFrame,
        manifest: String,
        total: usize,
        offset: usize,
        mut records: Vec<ChannelRecord>,
        fragment: Option<PageFragment>,
    ) -> Result<(), ChannelRuntimeError> {
        let mut next = self.recovery.checkpoint.clone();
        if !self.recovery.has_source(frame) || !next.journal_complete {
            return Ok(());
        }
        next.progress
            .check(&frame.request_id, offset, &manifest, total, records.len())
            .map_err(ChannelRuntimeError::Codec)?;
        assemble_records(&mut next, &mut records, fragment)?;
        let (rows, keys) = self.prepare_imported_rows(records, &frame.sender_key)?;
        next.progress
            .advance(&manifest, total, rows.len(), next.partial.is_some())
            .map_err(ChannelRuntimeError::Codec)?;
        let receipts = self.history_receipts(frame, &next, offset, &keys)?;
        Recovery::finished(&mut next, &frame.sender_key);
        self.save_history_rows(next, &rows, &receipts)?;
        self.recovery.last_progress = crate::conversation::now_ms();
        self.pull_history(self.recovery.last_progress)
    }

    fn prepare_imported_rows(
        &self,
        records: Vec<ChannelRecord>,
        holder: &str,
    ) -> Result<(Vec<StoredMessage<ChannelMessage>>, Vec<HistoryKey>), ChannelRuntimeError> {
        let mut rows = Vec::new();
        let mut keys = Vec::new();
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
            keys.push(HistoryKey {
                message_id: record.message_id.clone(),
                sent_at_ms: record.sent_at_ms,
                digest: record
                    .binding_digest()
                    .map_err(ChannelRuntimeError::Codec)?,
            });
            rows.push(self.history_row_for(record, holder)?);
        }
        Ok((rows, keys))
    }

    fn history_receipts(
        &self,
        frame: &HistoryFrame,
        next: &Checkpoint,
        offset: usize,
        keys: &[HistoryKey],
    ) -> Result<Vec<EvidenceWrite>, ChannelRuntimeError> {
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
                .recovery_digest_with_tail(&prefix, Some(&self.deletions.context), keys)?
                != next.progress.manifest.as_deref().unwrap_or_default()
        {
            return Err(ChannelRuntimeError::Codec(
                "history frozen manifest differs".into(),
            ));
        }
        keys.iter()
            .enumerate()
            .map(|(index, key)| {
                Ok(EvidenceWrite {
                    key: format!("{prefix}{:020}", offset + index),
                    bytes: serde_json::to_vec(key)
                        .map_err(|e| ChannelRuntimeError::Codec(e.to_string()))?,
                })
            })
            .collect()
    }
}

fn assemble_records(
    next: &mut Checkpoint,
    records: &mut Vec<ChannelRecord>,
    fragment: Option<PageFragment>,
) -> Result<(), ChannelRuntimeError> {
    if let Some(fragment) = fragment {
        if !records.is_empty() {
            return Err(ChannelRuntimeError::Codec("mixed history fragment".into()));
        }
        if let Some(bytes) = PartialRecord::accept(&mut next.partial, fragment)
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
    Ok(())
}
