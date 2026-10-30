//! Freeze ordinary stored rows only after the recipient's own membership check.
use super::*;
use super::{
    protocol::{CheckedFrame, GroupScope},
    records::GroupRecord,
};
use crate::conversation::recovery::{
    manifest::Manifest,
    wire::{HistoryFrame, HistoryMessage, HistoryPull},
};

#[derive(Clone, Serialize, Deserialize)]
struct Export {
    round: u64,
    request_id: String,
    manifest: Manifest,
    deletion_digest: String,
    expires_ms: u64,
}

impl GroupSession {
    pub(super) fn answer_history(
        &mut self,
        checked: CheckedFrame,
        pull: Option<HistoryPull>,
    ) -> Result<(), PrivateGroupError> {
        let (message, erased_fragment) = match self.history_answer(
            &checked.frame,
            &checked.body.scope,
            pull,
            checked.body.partial_digest.as_deref(),
        ) {
            Ok(message) => message,
            Err(error) => {
                dlog::write(
                    LogLevel::Warn,
                    kinds::FRAME,
                    &self.group_id,
                    &format!("group history source: {error}"),
                );
                (HistoryMessage::Unavailable, false)
            }
        };
        let scope = self.own_history_scope()?;
        self.dispatch_history_body(
            Some(checked.frame.sender_key),
            checked.frame.request_id,
            checked.frame.round,
            super::protocol::GroupBody {
                scope,
                message,
                evidence: None,
                partial_digest: None,
                erased_fragment,
            },
            checked.permit,
        )
    }

    fn history_answer(
        &mut self,
        frame: &HistoryFrame,
        recipient: &GroupScope,
        pull: Option<HistoryPull>,
        partial_digest: Option<&str>,
    ) -> Result<(HistoryMessage<GroupRecord>, bool), PrivateGroupError> {
        self.validate_history_scope(recipient, &frame.sender_key)?;
        let Some(pull) = pull else {
            return Ok((self.history_offer(recipient)?, false));
        };
        let prefix = format!(
            "{}\u{1}export-data\u{1}{}",
            self.deletions.context, frame.sender_key
        );
        let meta_key = format!(
            "{}\u{1}export-meta\u{1}{}",
            self.deletions.context, frame.sender_key
        );
        let mut export = self
            .persistence
            .as_ref()
            .ok_or(PrivateGroupError::NotReady)?
            .recovery_state::<Export>(&meta_key)?;
        if export.as_ref().is_none_or(|e| e.round < frame.round) && pull.offset == 0 {
            let current = self.history_manifest(recipient)?;
            if current.digest == pull.manifest
                && self.history_deletion_digest()? == pull.deletion_digest
            {
                export = Some(self.freeze_history_export(
                    frame,
                    current,
                    &pull.deletion_digest,
                    &prefix,
                    &meta_key,
                    recipient,
                )?);
            }
        }
        // Nothing frozen for this round: this source changed since its offer,
        // so it offers its current view instead of turning the reader away.
        if pull.is_first() && export.as_ref().is_none_or(|e| e.round < frame.round) {
            return Ok((self.history_offer(recipient)?, false));
        }
        let Some(export) = export.filter(|e| e.matches(frame, &pull)) else {
            return Ok((HistoryMessage::Unavailable, false));
        };
        if pull.journal {
            self.history_journal_page(&prefix, &pull)
                .map(|message| (message, false))
        } else {
            self.history_content_page(
                &prefix,
                export.manifest.total,
                &pull,
                recipient,
                &frame.sender_key,
                partial_digest,
            )
        }
    }

    fn history_offer(
        &mut self,
        recipient: &GroupScope,
    ) -> Result<HistoryMessage<GroupRecord>, PrivateGroupError> {
        let current = self.history_manifest(recipient)?;
        Ok(HistoryMessage::Offer {
            manifest: current.digest,
            total: current.total,
            deletion_digest: self.history_deletion_digest()?,
        })
    }

    fn history_manifest(&mut self, recipient: &GroupScope) -> Result<Manifest, PrivateGroupError> {
        let recipient_key = crate::conversation::recovery::manifest::digest(recipient)
            .map_err(PrivateGroupError::Codec)?;
        let generation = super::source_cache::Generation {
            messages: self.messages.revision(),
            head: recipient.head.clone(),
            deletions: self.history_deletion_digest()?,
        };
        if let Some(manifest) = self.history_exports.get(generation, &recipient_key) {
            return Ok(manifest);
        }
        let manifest = self
            .persistence
            .as_ref()
            .ok_or(PrivateGroupError::NotReady)?
            .recovery_manifest(GROUP_HISTORY, &self.group_id, |row| {
                self.eligible_history_key(row, recipient)
            })?;
        self.history_exports.insert(recipient_key, manifest.clone());
        Ok(manifest)
    }

    fn freeze_history_export(
        &mut self,
        frame: &HistoryFrame,
        manifest: Manifest,
        deletion_digest: &str,
        prefix: &str,
        meta_key: &str,
        recipient: &GroupScope,
    ) -> Result<Export, PrivateGroupError> {
        let next = Export {
            round: frame.round,
            request_id: frame.request_id.clone(),
            manifest,
            deletion_digest: deletion_digest.into(),
            expires_ms: now_ms().saturating_add(120_000),
        };
        let authority = self.deletion_authority()?;
        self.persistence
            .as_ref()
            .ok_or(PrivateGroupError::NotReady)?
            .freeze_recovery(
                GROUP_HISTORY,
                &self.group_id,
                crate::persistence::FrozenExport {
                    prefix,
                    meta_key,
                    header: &next,
                    manifest: &next.manifest,
                },
                |row| self.eligible_history_key(row, recipient),
                self.deletions
                    .records
                    .values()
                    .filter(|r| {
                        r.scope == crate::message_deletion::DeleteScope::ForEveryone
                            && r.status != crate::message_deletion::DeletionStatus::Rejected
                            && authority.validate(r, &authority.local.key).is_ok()
                    })
                    .cloned(),
            )?;
        Ok(next)
    }
}

impl Export {
    fn matches(&self, frame: &HistoryFrame, pull: &HistoryPull) -> bool {
        self.round == frame.round
            && self.request_id == frame.request_id
            && self.manifest.digest == pull.manifest
            && self.deletion_digest == pull.deletion_digest
            && pull.offset <= self.manifest.total
            && self.expires_ms > now_ms()
    }
}

#[cfg(test)]
#[path = "source_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "source_cache_tests.rs"]
mod cache_tests;
