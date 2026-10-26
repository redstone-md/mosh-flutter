use super::*;

#[derive(Clone, Serialize, Deserialize)]
struct Export {
    round: u64,
    request_id: String,
    manifest: Manifest,
    deletion_digest: String,
    expires_ms: u64,
}

impl ChannelSession {
    pub(super) fn answer_history(&mut self, frame: &HistoryFrame, pull: Option<HistoryPull>) {
        let result = if let Some(pull) = pull {
            self.serve_history(frame, pull)
        } else {
            self.offer_history(frame)
        };
        if let Err(error) = result {
            dlog::write(
                LogLevel::Warn,
                kinds::FRAME,
                &self.name,
                &format!("history source: {error}"),
            );
            let _ = self.reply_history(
                Some(frame.sender_key.clone()),
                frame.request_id.clone(),
                frame.round,
                HistoryMessage::Unavailable,
            );
        }
    }

    fn offer_history(&mut self, frame: &HistoryFrame) -> Result<(), ChannelRuntimeError> {
        let manifest = self.history_manifest()?;
        self.reply_history(
            Some(frame.sender_key.clone()),
            frame.request_id.clone(),
            frame.round,
            HistoryMessage::Offer {
                manifest: manifest.digest,
                total: manifest.total,
                deletion_digest: self.history_deletion_digest()?,
            },
        )
    }

    pub(super) fn history_manifest(&mut self) -> Result<Manifest, ChannelRuntimeError> {
        let count = self.messages.revision();
        if let Some((version, manifest)) = &self.recovery.cache {
            if *version == count {
                return Ok(manifest.clone());
            }
        }
        let store =
            self.deletions.store.as_ref().ok_or_else(|| {
                ChannelRuntimeError::Persistence("history store unavailable".into())
            })?;
        let manifest = store.recovery_manifest(CHANNEL_HISTORY, &self.name, ChannelRecord::key)?;
        self.recovery.cache = Some((count, manifest.clone()));
        Ok(manifest)
    }

    pub(super) fn serve_history(
        &mut self,
        frame: &HistoryFrame,
        pull: HistoryPull,
    ) -> Result<(), ChannelRuntimeError> {
        let prefix = format!(
            "{}\u{1}export-data\u{1}{}",
            self.deletions.context, frame.sender_key
        );
        let meta_key = format!(
            "{}\u{1}export-meta\u{1}{}",
            self.deletions.context, frame.sender_key
        );
        let current = self.history_manifest()?;
        let store = self.deletions.store.as_ref().unwrap();
        let mut export = store.recovery_state::<Export>(&meta_key)?;
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
            return self.reply_history(
                Some(frame.sender_key.clone()),
                frame.request_id.clone(),
                frame.round,
                HistoryMessage::Unavailable,
            );
        };
        let message = if pull.journal {
            self.history_journal_page(&prefix, &pull)?
        } else {
            self.history_content_page(&prefix, export.manifest.total, &pull)?
        };
        self.reply_history(
            Some(frame.sender_key.clone()),
            frame.request_id.clone(),
            frame.round,
            message,
        )
    }

    fn freeze_history_export(
        &self,
        frame: &HistoryFrame,
        manifest: Manifest,
        deletion_digest: &str,
        prefix: &str,
        meta_key: &str,
    ) -> Result<Export, ChannelRuntimeError> {
        let next = Export {
            round: frame.round,
            request_id: frame.request_id.clone(),
            manifest,
            deletion_digest: deletion_digest.into(),
            expires_ms: crate::conversation::now_ms().saturating_add(120_000),
        };
        let authority = self.deletion_authority()?;
        self.deletions.store.as_ref().unwrap().freeze_recovery(
            CHANNEL_HISTORY,
            &self.name,
            crate::persistence::FrozenExport {
                prefix,
                meta_key,
                header: &next,
                manifest: &next.manifest,
            },
            ChannelRecord::key,
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
            && self.expires_ms > crate::conversation::now_ms()
    }
}
