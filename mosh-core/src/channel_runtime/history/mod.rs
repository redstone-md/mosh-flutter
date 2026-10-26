//! Public channel recovery over the existing room and shared durable importer.
use super::*;
use crate::conversation::recovery::{
    manifest::Manifest,
    wire::{HistoryFrame, HistoryMessage},
    HistorySync, HistorySyncReason, HistorySyncState,
};

mod journal;
mod receive;
mod records;
mod source;
use records::ChannelRecord;

use crate::conversation::recovery::coordinator::Checkpoint;
pub(super) use crate::conversation::recovery::coordinator::Coordinator as Recovery;

impl ChannelSession {
    pub(super) fn history_state(&self) -> Option<HistorySync> {
        self.deletions.store.as_ref()?;
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

    pub(super) fn restore_history(&mut self) {
        let Some(store) = &self.deletions.store else {
            return;
        };
        match store.recovery_state::<Checkpoint>(&self.checkpoint_key()) {
            Ok(checkpoint) => {
                self.recovery.checkpoint = checkpoint.unwrap_or_default();
                self.recovery.error = None;
                self.recovery.restored = true;
                self.recovery.last_progress = crate::conversation::now_ms();
            }
            Err(_) => self.recovery.error = Some(HistorySyncReason::StorageRefused),
        }
    }

    pub(super) fn queue_history(&mut self, frame: HistoryFrame) -> Result<(), ChannelRuntimeError> {
        let _: HistoryMessage<ChannelRecord> = frame
            .open(&self.deletions.context, &self.mesh_id, &self.blob_topic)
            .map_err(ChannelRuntimeError::Codec)?;
        if frame.sender_key == self.device_fingerprint
            || frame
                .recipient_key
                .as_ref()
                .is_some_and(|p| p != &self.device_fingerprint)
        {
            return Ok(());
        }
        self.recovery
            .queue(frame)
            .map_err(ChannelRuntimeError::Codec)?;
        Ok(())
    }

    pub(super) fn sync_history(&mut self, now: u64) -> Result<bool, ChannelRuntimeError> {
        if self.deletions.store.is_none() {
            return Ok(false);
        }
        if !self.recovery.restored {
            self.restore_history();
            if !self.recovery.restored {
                return Ok(false);
            }
        }
        if self.recovery.checkpoint.source.is_some() && self.recovery.permit.is_none() {
            self.recovery.permit = crate::conversation::recovery::slots::ImportPermit::acquire(
                &self.device_fingerprint,
                &self.deletions.context,
            );
            if self.recovery.permit.is_none() {
                return Ok(false);
            }
        }
        self.recovery.observe(
            crate::moss_ffi::connected_peer_revision(),
            self.messages.revision(),
        );
        let mut changed = false;
        for frame in self.recovery.drain() {
            match self.receive_history(frame) {
                Ok(imported) => changed |= imported,
                Err(error) => {
                    self.recovery.error =
                        Some(if matches!(error, ChannelRuntimeError::Persistence(_)) {
                            HistorySyncReason::StorageRefused
                        } else {
                            HistorySyncReason::EvidenceMissing
                        });
                    dlog::write(
                        LogLevel::Warn,
                        kinds::FRAME,
                        &self.name,
                        &format!("history: {error}"),
                    );
                }
            }
        }
        if self.recovery.checkpoint.source.is_some()
            && now.saturating_sub(self.recovery.last_progress) < 10_000
        {
            if now.saturating_sub(self.recovery.last_pull) >= 2000 {
                self.pull_history(now)?;
            }
        } else if self.recovery.probe_due(now) {
            self.recovery.permit = None;
            let next = self
                .recovery
                .begin_round()
                .map_err(ChannelRuntimeError::Codec)?;
            self.save_checkpoint(next, &[])?;
            self.recovery.probed(now);
            self.send_history(None, HistoryMessage::Probe)?;
        }
        Ok(changed)
    }

    fn checkpoint_key(&self) -> String {
        format!("{}\u{1}local", self.deletions.context)
    }

    fn send_history(
        &self,
        recipient: Option<String>,
        message: HistoryMessage<ChannelRecord>,
    ) -> Result<(), ChannelRuntimeError> {
        self.reply_history(
            recipient,
            self.recovery.checkpoint.progress.request_id.clone(),
            self.recovery.checkpoint.round,
            message,
        )
    }

    fn reply_history(
        &self,
        recipient: Option<String>,
        request_id: String,
        round: u64,
        message: HistoryMessage<ChannelRecord>,
    ) -> Result<(), ChannelRuntimeError> {
        let key = self
            .node
            .identity_signer()
            .map_err(|e| ChannelRuntimeError::Moss(e.to_string()))?;
        let mut frame = HistoryFrame {
            version: 1,
            conversation: self.deletions.context.clone(),
            mesh_id: self.mesh_id.clone(),
            channel: self.blob_topic.clone(),
            sender_key: String::new(),
            recipient_key: recipient,
            request_id,
            round,
            payload_b64: String::new(),
            signature: String::new(),
        };
        frame
            .seal(key, &message)
            .map_err(ChannelRuntimeError::Codec)?;
        publish_json(
            &self.node,
            &self.mesh_id,
            &self.blob_topic,
            &ChannelBlobEnvelope::History { frame },
        )
    }
}

#[cfg(test)]
mod tests;

#[cfg(test)]
mod tests_admission;

#[cfg(test)]
mod tests_deletion;
