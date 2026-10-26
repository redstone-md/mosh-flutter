//! Shared source rounds are restored against the installation's own current head.
use super::*;
use crate::conversation::recovery::{
    coordinator::Checkpoint, wire::HistoryMessage, HistorySync, HistorySyncReason, HistorySyncState,
};
#[derive(Serialize, Deserialize)]
pub(super) struct GroupCheckpoint {
    pub(super) checkpoint: Checkpoint,
    pub(super) head: super::protocol::CurrentHead,
}
impl GroupSession {
    pub(in crate::private_group_runtime) fn history_state(&self) -> Option<HistorySync> {
        self.persistence.as_ref()?;
        Some(HistorySync {
            state: if self.recovery.checkpoint.progress.complete {
                HistorySyncState::Complete
            } else if self.recovery.checkpoint.source.is_some() && self.recovery.error.is_none() {
                HistorySyncState::Importing
            } else {
                HistorySyncState::WaitingForSource
            },
            reason: self.recovery.error.or_else(|| {
                (!self.recovery.checkpoint.progress.complete
                    && self.recovery.checkpoint.source.is_none())
                .then_some(HistorySyncReason::SourceUnavailable)
            }),
        })
    }

    pub(in crate::private_group_runtime) fn sync_history(
        &mut self,
        now: u64,
    ) -> Result<(), PrivateGroupError> {
        if self.persistence.is_none() || !self.joined || !self.crypto.is_ready() {
            return Ok(());
        }
        self.restore_history()?;
        let current_head = self.current_history_head()?;
        if self.history_head.as_ref() != Some(&current_head) {
            self.history_dispatch.invalidate();
            self.recovery = Default::default();
            self.restore_history()?;
        }
        self.recovery.observe(
            crate::moss_ffi::connected_peer_revision(),
            self.messages.revision(),
        );
        self.drain_history_frames();
        if self.recovery.checkpoint.source.is_some()
            && now.saturating_sub(self.recovery.last_progress) < 10_000
        {
            if now.saturating_sub(self.recovery.last_pull) >= 2000 {
                self.pull_history(now)?;
            }
        } else if self.recovery.source_timed_out(now) || self.recovery.probe_due(now) {
            if self.recovery.source_timed_out(now) {
                self.recovery.failed(now);
            }
            self.recovery.permit = None;
            let next = self
                .recovery
                .begin_round()
                .map_err(PrivateGroupError::Codec)?;
            self.save_history(next, &[], &[], &[])?;
            self.recovery.probed(now);
            self.send_history(None, HistoryMessage::Probe)?;
        }
        Ok(())
    }

    fn restore_history(&mut self) -> Result<(), PrivateGroupError> {
        if self.recovery.restored {
            return Ok(());
        }
        let head = self.current_history_head()?;
        self.recovery.checkpoint = self
            .persistence
            .as_ref()
            .ok_or(PrivateGroupError::NotReady)?
            .recovery_state::<GroupCheckpoint>(&self.checkpoint_key())?
            .filter(|saved| saved.head == head)
            .map(|saved| saved.checkpoint)
            .unwrap_or_default();
        self.history_head = Some(head);
        self.recovery.restored = true;
        self.recovery.last_progress = now_ms();
        Ok(())
    }

    pub(super) fn checkpoint_key(&self) -> String {
        format!("{}\u{1}local", self.deletions.context)
    }
}
