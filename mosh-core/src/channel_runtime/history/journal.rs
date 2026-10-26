//! Existing deletion authority is a prerequisite, never a source-granted right.
use super::*;
use crate::message_deletion::protocol::DeletionMessage;
use ed25519_dalek::Signer;

impl ChannelSession {
    pub(super) fn history_deletion_digest(&self) -> Result<String, ChannelRuntimeError> {
        crate::message_deletion::shared::digest(&self.deletions, &self.deletion_authority()?)
            .map_err(ChannelRuntimeError::Codec)
    }

    pub(super) fn import_history_journal(
        &mut self,
        frame: &HistoryFrame,
        manifest: String,
        digest: String,
        page: DeletionMessage,
    ) -> Result<(), ChannelRuntimeError> {
        let mut next = self.recovery.checkpoint.clone();
        if next.round != frame.round
            || next.source.as_ref() != Some(&frame.sender_key)
            || next.progress.request_id != frame.request_id
            || next.journal_complete
            || next.progress.manifest.as_ref() != Some(&manifest)
            || next.deletion_digest != digest
        {
            return Ok(());
        }
        let Some(page) = self.assemble_history_journal(&mut next, page)? else {
            self.save_checkpoint(next, &[])?;
            self.recovery.last_progress = crate::conversation::now_ms();
            return self.pull_history(self.recovery.last_progress);
        };
        let DeletionMessage::State {
            records,
            next: after,
        } = &page
        else {
            return Err(ChannelRuntimeError::Codec(
                "invalid history deletion journal".into(),
            ));
        };
        validate_window(records, next.journal_after.as_deref(), after.as_deref())?;
        self.apply_history_deletions(&page, records, &frame.sender_key)?;
        self.retain_source_journal(&frame.request_id, records, &digest, after.is_none())?;
        next.journal_complete = after.is_none();
        next.journal_after = after.clone();
        self.save_checkpoint(next, &[])?;
        self.recovery.last_progress = crate::conversation::now_ms();
        self.pull_history(self.recovery.last_progress)
    }

    fn retain_source_journal(
        &self,
        request_id: &str,
        records: &[crate::message_deletion::DeletionRecord],
        digest: &str,
        complete: bool,
    ) -> Result<(), ChannelRuntimeError> {
        let store = self.deletions.store.as_ref().unwrap();
        let prefix = format!(
            "{}\u{1}request\u{1}{}\u{1}journal\u{1}",
            self.checkpoint_key(),
            request_id
        );
        for record in records {
            store.save_recovery(&format!("{prefix}{}", record.storage_key()), record)?;
        }
        if complete && store.recovery_sequence_digest(&prefix)? != digest {
            return Err(ChannelRuntimeError::Codec(
                "history deletion digest differs".into(),
            ));
        }
        Ok(())
    }

    fn apply_history_deletions(
        &mut self,
        page: &DeletionMessage,
        records: &[crate::message_deletion::DeletionRecord],
        holder: &str,
    ) -> Result<(), ChannelRuntimeError> {
        let authority = self.deletion_authority()?;
        for record in records {
            authority
                .validate(record, holder)
                .map_err(ChannelRuntimeError::Codec)?;
        }
        let key = self
            .node
            .identity_signer()
            .map_err(|e| ChannelRuntimeError::Moss(e.to_string()))?;
        crate::message_deletion::DeletionContext {
            book: &mut self.deletions,
            log: &mut self.messages,
            attempts: &mut self.outbound_attempts,
            transfer: &mut self.transfer,
        }
        .receive(page.clone(), holder, &authority, |bytes| {
            Ok(hex::encode(key.sign(bytes).to_bytes()))
        })
        .map_err(ChannelRuntimeError::Codec)?;
        Ok(())
    }

    fn assemble_history_journal(
        &self,
        next: &mut Checkpoint,
        page: DeletionMessage,
    ) -> Result<Option<DeletionMessage>, ChannelRuntimeError> {
        if let DeletionMessage::Fragment(fragment) = page {
            return crate::conversation::recovery::fragment::PartialRecord::accept(
                &mut next.partial,
                fragment,
            )
            .map_err(ChannelRuntimeError::Codec)?
            .map(|bytes| {
                serde_json::from_slice(&bytes)
                    .map_err(|e| ChannelRuntimeError::Codec(e.to_string()))
            })
            .transpose();
        }
        if next.partial.is_some() {
            return Err(ChannelRuntimeError::Codec(
                "history journal partial missing".into(),
            ));
        }
        Ok(Some(page))
    }
}

fn validate_window(
    records: &[crate::message_deletion::DeletionRecord],
    previous: Option<&str>,
    next: Option<&str>,
) -> Result<(), ChannelRuntimeError> {
    let mut last = previous.map(str::to_owned);
    for record in records {
        let key = record.storage_key();
        if last.as_ref().is_some_and(|old| old >= &key) {
            return Err(ChannelRuntimeError::Codec(
                "history journal keys are not ordered".into(),
            ));
        }
        last = Some(key);
    }
    if records.len() > 16
        || next.is_some_and(|next| records.is_empty() || last.as_deref() != Some(next))
    {
        return Err(ChannelRuntimeError::Codec(
            "history journal makes no progress".into(),
        ));
    }
    Ok(())
}
