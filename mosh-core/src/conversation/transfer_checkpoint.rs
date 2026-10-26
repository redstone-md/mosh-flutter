//! Durable chunk recovery never invents another peer or execution grant.
use super::*;
use crate::persistence::user_transfers::types::{
    UserTransferDirection as Direction, UserTransferState as State,
};

impl Transfer {
    pub(super) fn restore_execution_checkpoints(&mut self) {
        let Some(context) = &self.execution else {
            return;
        };
        let records = match context.store.user_transfers() {
            Ok(records) => records
                .into_iter()
                .filter(|record| {
                    record.target == context.target && record.direction == Direction::Download
                })
                .collect::<Vec<_>>(),
            Err(error) => {
                self.execution.as_mut().unwrap().error = Some(error.to_string());
                return;
            }
        };
        for record in records {
            let Some(id) = record.attachment_id else {
                continue;
            };
            if record.state == State::Cancelled || self.slots.cached_descriptor(&id).is_some() {
                continue;
            }
            let Some(manifest) = self.manifest_for(&id) else {
                continue;
            };
            let context = self.execution.as_ref().unwrap();
            let result = (|| -> Result<(), TransferError> {
                let saved = context
                    .store
                    .user_transfer(&record.id)
                    .map_err(|error| TransferError::Bytes(error.to_string()))?
                    .ok_or_else(|| TransferError::Bytes("transfer checkpoint missing".into()))?;
                if saved.manifest.as_ref().is_none_or(|old| {
                    old.content_hash != manifest.content_hash || old.attachment_id != id
                }) {
                    return Err(TransferError::Bytes(
                        "transfer checkpoint binding mismatch".into(),
                    ));
                }
                let frames = context
                    .store
                    .user_transfer_chunks(&record.id)
                    .map_err(|error| TransferError::Bytes(error.to_string()))?;
                self.slots.start_download(&id, &mut self.runtime)?;
                for frame in frames {
                    if let ChunkOutcome::Complete {
                        bytes,
                        content_hash,
                        ..
                    } = self.runtime.ingest_chunk(&frame)?
                    {
                        let path =
                            self.store
                                .write_blob(&content_hash, &manifest.file_name, &bytes)?;
                        self.slots
                            .complete_download(&id, path.to_string_lossy().into_owned());
                    }
                }
                let state = if self.slots.cached_descriptor(&id).is_some() {
                    State::Complete
                } else {
                    State::Paused
                };
                context
                    .store
                    .set_user_transfer_state(&record.id, state)
                    .map_err(|error| TransferError::Bytes(error.to_string()))?;
                Ok(())
            })();
            if let Err(error) = result {
                self.slots.fail(&id);
                self.execution.as_mut().unwrap().error = Some(error.to_string());
            }
        }
    }

    pub(super) fn checkpoint_frame(&mut self, frame: &ChunkFrame) -> Result<(), TransferError> {
        let Some(context) = &mut self.execution else {
            return Ok(());
        };
        if !context.admissions.contains_key(&frame.attachment_id) {
            return Ok(());
        }
        let batch = context
            .checkpoints
            .entry(frame.attachment_id.clone())
            .or_default();
        batch.push(frame.clone());
        if batch.len() >= 64 {
            self.flush_checkpoints()?;
        }
        Ok(())
    }

    /// Existing protocol/status turns flush a bounded batch; final file commit
    /// and cancellation flush synchronously. A crash loses at most 256 KiB of
    /// received-but-uncommitted bytes, which the receiver requests again.
    pub(super) fn flush_checkpoints(&mut self) -> Result<(), TransferError> {
        let Some(context) = &mut self.execution else {
            return Ok(());
        };
        let batches = std::mem::take(&mut context.checkpoints);
        for (attachment, frames) in batches {
            let Some(admission) = context.admissions.get(&attachment) else {
                continue;
            };
            if let Err(error) = context
                .store
                .save_user_transfer_chunks(&admission.id, &frames)
            {
                self.slots.fail(&attachment);
                self.runtime.fail_incoming(&attachment);
                context.error = Some(error.to_string());
                return Err(TransferError::Bytes(error.to_string()));
            }
        }
        Ok(())
    }
}
