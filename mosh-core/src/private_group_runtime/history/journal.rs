//! Deletion signatures retain existing MLS authority before any recovered row is visible.
use super::protocol::CheckedFrame;
use super::*;
use crate::conversation::recovery::{coordinator::Checkpoint, fragment::PartialRecord};
use crate::message_deletion::{protocol::DeletionMessage, DeletionContext};

impl GroupSession {
    pub(super) fn history_deletion_digest(&mut self) -> Result<String, PrivateGroupError> {
        let authority = self.deletion_authority()?;
        crate::message_deletion::shared::digest(&self.deletions, &authority)
            .map_err(PrivateGroupError::Codec)
    }

    pub(super) fn import_history_journal(
        &mut self,
        checked: &CheckedFrame,
        manifest: String,
        digest: String,
        page: DeletionMessage,
    ) -> Result<(), PrivateGroupError> {
        let mut next = self.recovery.checkpoint.clone();
        if !self.recovery.has_source(&checked.frame)
            || next.journal_complete
            || next.progress.manifest.as_ref() != Some(&manifest)
            || next.deletion_digest != digest
        {
            return Ok(());
        }
        let Some(page) = assemble_journal(&mut next, page)? else {
            self.save_history(next, &[], &[], &[])?;
            self.recovery.last_progress = now_ms();
            return self.pull_history(now_ms());
        };
        let DeletionMessage::State {
            records,
            next: after,
        } = &page
        else {
            return Err(PrivateGroupError::Codec(
                "invalid group history deletion journal".into(),
            ));
        };
        validate_window(records, next.journal_after.as_deref(), after.as_deref())?;
        let holder = hex::encode(&checked.sender.mls_signer);
        self.apply_history_deletions(&page, records, &holder)?;
        let prefix = format!(
            "{}\u{1}request\u{1}{}\u{1}journal\u{1}",
            self.checkpoint_key(),
            checked.frame.request_id
        );
        let store = self
            .persistence
            .as_ref()
            .ok_or(PrivateGroupError::NotReady)?;
        for record in records {
            store.save_recovery(&format!("{prefix}{}", record.storage_key()), record)?;
        }
        if after.is_none() && store.recovery_sequence_digest(&prefix)? != digest {
            return Err(PrivateGroupError::Codec(
                "group history deletion digest differs".into(),
            ));
        }
        next.journal_complete = after.is_none();
        next.journal_after = after.clone();
        self.save_history(next, &[], &[], &[])?;
        self.recovery.last_progress = now_ms();
        self.pull_history(now_ms())
    }

    fn apply_history_deletions(
        &mut self,
        page: &DeletionMessage,
        records: &[crate::message_deletion::DeletionRecord],
        holder: &str,
    ) -> Result<(), PrivateGroupError> {
        let authority = self.deletion_authority()?;
        for record in records {
            authority
                .validate(record, holder)
                .map_err(PrivateGroupError::Codec)?;
        }
        DeletionContext {
            book: &mut self.deletions,
            log: &mut self.messages,
            attempts: &mut self.outbound_attempts,
            transfer: &mut self.transfer,
        }
        .receive(page.clone(), holder, &authority, |bytes| {
            self.crypto
                .sign_sender_proof(bytes)
                .map(hex::encode)
                .map_err(|e| e.to_string())
        })
        .map_err(PrivateGroupError::Codec)?;
        Ok(())
    }
}

fn assemble_journal(
    next: &mut Checkpoint,
    page: DeletionMessage,
) -> Result<Option<DeletionMessage>, PrivateGroupError> {
    if let DeletionMessage::Fragment(fragment) = page {
        return PartialRecord::accept(&mut next.partial, fragment)
            .map_err(PrivateGroupError::Codec)?
            .map(|bytes| {
                serde_json::from_slice(&bytes).map_err(|e| PrivateGroupError::Codec(e.to_string()))
            })
            .transpose();
    }
    if next.partial.is_some() {
        return Err(PrivateGroupError::Codec(
            "group history journal partial missing".into(),
        ));
    }
    Ok(Some(page))
}

fn validate_window(
    records: &[crate::message_deletion::DeletionRecord],
    previous: Option<&str>,
    next: Option<&str>,
) -> Result<(), PrivateGroupError> {
    let mut last = previous.map(str::to_owned);
    for record in records {
        let key = record.storage_key();
        if last.as_ref().is_some_and(|old| old >= &key) {
            return Err(PrivateGroupError::Codec(
                "history journal keys are not ordered".into(),
            ));
        }
        last = Some(key);
    }
    if records.len() > 16
        || next.is_some_and(|next| records.is_empty() || last.as_deref() != Some(next))
    {
        return Err(PrivateGroupError::Codec(
            "history journal makes no progress".into(),
        ));
    }
    Ok(())
}
