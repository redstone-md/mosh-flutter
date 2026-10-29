use super::*;

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
                self.answer_history(&frame, None);
            }
            HistoryMessage::Pull(pull) => self.answer_history(&frame, Some(pull)),
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
        if let Some(next) = self
            .recovery
            .reoffered(frame, &manifest, total, &deletion_digest)
        {
            self.save_checkpoint(next, &[])?;
            self.recovery.last_progress = crate::conversation::now_ms();
            return self.pull_history(self.recovery.last_progress);
        }
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
}
