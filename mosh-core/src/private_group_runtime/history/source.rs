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
        let message = match self.history_answer(&checked.frame, &checked.body.scope, pull) {
            Ok(message) => message,
            Err(error) => {
                dlog::write(
                    LogLevel::Warn,
                    kinds::FRAME,
                    &self.group_id,
                    &format!("group history source: {error}"),
                );
                HistoryMessage::Unavailable
            }
        };
        self.reply_history(
            Some(checked.frame.sender_key),
            checked.frame.request_id,
            checked.frame.round,
            message,
            checked.permit,
        )
    }

    fn history_answer(
        &mut self,
        frame: &HistoryFrame,
        recipient: &GroupScope,
        pull: Option<HistoryPull>,
    ) -> Result<HistoryMessage<GroupRecord>, PrivateGroupError> {
        let current = self.history_manifest()?;
        let Some(pull) = pull else {
            return Ok(HistoryMessage::Offer {
                manifest: current.digest,
                total: current.total,
                deletion_digest: self.history_deletion_digest()?,
            });
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
        if export.as_ref().is_none_or(|e| e.round < frame.round)
            && pull.offset == 0
            && current.digest == pull.manifest
            && self.history_deletion_digest()? == pull.deletion_digest
        {
            export = Some(self.freeze_history_export(
                frame,
                current,
                &pull.deletion_digest,
                &prefix,
                &meta_key,
            )?);
        }
        let Some(export) = export.filter(|e| e.matches(frame, &pull)) else {
            return Ok(HistoryMessage::Unavailable);
        };
        if pull.journal {
            self.history_journal_page(&prefix, &pull)
        } else {
            self.history_content_page(
                &prefix,
                export.manifest.total,
                &pull,
                recipient,
                &frame.sender_key,
            )
        }
    }

    fn history_manifest(&mut self) -> Result<Manifest, PrivateGroupError> {
        if let Some((revision, manifest)) = &self.recovery.cache {
            if *revision == self.messages.revision() {
                return Ok(manifest.clone());
            }
        }
        let manifest = self
            .persistence
            .as_ref()
            .ok_or(PrivateGroupError::NotReady)?
            .recovery_manifest(GROUP_HISTORY, &self.group_id, |row| {
                GroupRecord::key(row, &self.deletions.context, &self.mesh_id)
            })?;
        self.recovery.cache = Some((self.messages.revision(), manifest.clone()));
        Ok(manifest)
    }

    fn freeze_history_export(
        &mut self,
        frame: &HistoryFrame,
        manifest: Manifest,
        deletion_digest: &str,
        prefix: &str,
        meta_key: &str,
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
                |row| GroupRecord::key(row, &self.deletions.context, &self.mesh_id),
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
