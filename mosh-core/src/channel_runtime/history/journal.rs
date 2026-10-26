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
        let DeletionMessage::State {
            records,
            next: after,
        } = &page
        else {
            return Err(ChannelRuntimeError::Codec(
                "invalid history deletion journal".into(),
            ));
        };
        if records.len() > 16
            || after
                .as_ref()
                .is_some_and(|a| next.journal_after.as_ref().is_some_and(|old| old >= a))
        {
            return Err(ChannelRuntimeError::Codec(
                "history journal makes no progress".into(),
            ));
        }
        let authority = self.deletion_authority()?;
        for record in records {
            authority
                .validate(record, &frame.sender_key)
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
        .receive(page.clone(), &frame.sender_key, &authority, |bytes| {
            Ok(hex::encode(key.sign(bytes).to_bytes()))
        })
        .map_err(ChannelRuntimeError::Codec)?;
        let store = self.deletions.store.as_ref().unwrap();
        let prefix = format!(
            "{}\u{1}request\u{1}{}\u{1}journal\u{1}",
            self.checkpoint_key(),
            frame.request_id
        );
        for record in records {
            store.save_recovery(&format!("{prefix}{}", record.storage_key()), record)?;
        }
        if after.is_none() {
            if store.recovery_sequence_digest(&prefix)? != digest {
                return Err(ChannelRuntimeError::Codec(
                    "history deletion digest differs".into(),
                ));
            }
            next.journal_complete = true;
        }
        next.journal_after = after.clone();
        self.save_checkpoint(next, &[])?;
        self.recovery.last_progress = crate::conversation::now_ms();
        self.pull_history(self.recovery.last_progress)
    }
}
