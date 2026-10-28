//! Durable user admissions share the existing encrypted execution ledger.
use super::background_delivery::{decode, encode};
use super::*;
use crate::api::conversation::BridgeConversationRef;
use crate::attachment_runtime::{AttachmentManifest, MAX_ATTACHMENT_SIZE};
use types::{
    TransferRecord, UserTransfer, UserTransferDirection as Direction, UserTransferState as State,
};

mod checkpoints;
mod current;
pub(crate) mod types;
const PREFIX: &str = "transfer/";

impl Persistence {
    pub(crate) fn prepare_user_transfer(
        &self,
        target: BridgeConversationRef,
        direction: Direction,
        attachment_id: Option<String>,
        total_bytes: u64,
    ) -> Result<UserTransfer, PersistenceError> {
        if target.id.is_empty()
            || target.id.len() > 512
            || total_bytes == 0
            || total_bytes > MAX_ATTACHMENT_SIZE
            || (direction == Direction::Download
                && attachment_id.as_ref().is_none_or(String::is_empty))
        {
            return Err(invalid("invalid user attachment admission"));
        }
        let view = self.write(|tx| {
            let existing =
                self.matching_user_transfer(tx, &target, direction, attachment_id.as_deref())?;
            if direction == Direction::Upload && attachment_id.is_some() && existing.is_none() {
                return Err(invalid("upload has no local Send admission"));
            }
            let mut record = existing.unwrap_or_else(|| TransferRecord {
                view: UserTransfer {
                    id: format!("transfer-{}", hex::encode(rand::random::<[u8; 16]>())),
                    target,
                    attachment_id,
                    direction,
                    state: State::Prepared,
                    completed_bytes: 0,
                    total_bytes,
                    revision: 0,
                },
                manifest: None,
                receivers: Default::default(),
            });
            if record.view.total_bytes != total_bytes {
                return Err(invalid("transfer size changed"));
            }
            record.view.state = State::Prepared;
            record.view.revision = record
                .view
                .revision
                .checked_add(1)
                .ok_or_else(|| invalid("transfer revision exhausted"))?;
            Self::update_row(
                tx,
                BACKGROUND_DELIVERY,
                &key(&record.view.id)?,
                Some(&encrypt_blob(&self.dek, &encode(&record)?)?),
            )?;
            self.write_current_transfer(tx, &record.view)?;
            Ok(record.view)
        })?;
        crate::api::background::background_delivery_changed();
        Ok(view)
    }

    fn matching_user_transfer(
        &self,
        tx: &redb::WriteTransaction,
        target: &BridgeConversationRef,
        direction: Direction,
        attachment: Option<&str>,
    ) -> Result<Option<TransferRecord>, PersistenceError> {
        let Some(attachment) = attachment else {
            return Ok(None);
        };
        let rows = tx.open_table(BACKGROUND_DELIVERY).map_err(db_error)?;
        for row in rows.range(PREFIX.."transfer0").map_err(db_error)? {
            let (_, bytes) = row.map_err(db_error)?;
            let record: TransferRecord = decode(&decrypt_blob(&self.dek, bytes.value())?)?;
            if record.view.target == *target
                && record.view.direction == direction
                && record.view.attachment_id.as_deref() == Some(attachment)
            {
                return Ok(Some(record));
            }
        }
        Ok(None)
    }

    pub(crate) fn user_transfer(
        &self,
        id: &str,
    ) -> Result<Option<TransferRecord>, PersistenceError> {
        self.get(BACKGROUND_DELIVERY, &key(id)?)?
            .map(|value| decode(&value))
            .transpose()
    }

    pub(crate) fn user_transfers(&self) -> Result<Vec<UserTransfer>, PersistenceError> {
        let tx = self.db.begin_read().map_err(db_error)?;
        let rows = tx.open_table(BACKGROUND_DELIVERY).map_err(db_error)?;
        rows.range(PREFIX.."transfer0")
            .map_err(db_error)?
            .map(|row| {
                let (_, value) = row.map_err(db_error)?;
                let record: TransferRecord = decode(&decrypt_blob(&self.dek, value.value())?)?;
                Ok(record.view)
            })
            .collect()
    }

    pub(crate) fn bind_user_transfer(
        &self,
        id: &str,
        target: &BridgeConversationRef,
        manifest: &AttachmentManifest,
    ) -> Result<(), PersistenceError> {
        self.update_user_transfer(id, |record| {
            if record.view.target != *target
                || record.view.total_bytes != manifest.total_size
                || record
                    .view
                    .attachment_id
                    .as_ref()
                    .is_some_and(|value| value != &manifest.attachment_id)
                || record
                    .manifest
                    .as_ref()
                    .is_some_and(|value| value.content_hash != manifest.content_hash)
            {
                return Err(invalid("attachment admission binding mismatch"));
            }
            record.view.attachment_id = Some(manifest.attachment_id.clone());
            record.manifest = Some(manifest.clone());
            record.view.state = if record.view.direction == Direction::Upload {
                State::WaitingReceiver
            } else {
                State::WaitingExecution
            };
            Ok(())
        })
    }

    pub(crate) fn set_user_transfer_state(
        &self,
        id: &str,
        state: State,
    ) -> Result<(), PersistenceError> {
        self.update_user_transfer(id, |record| {
            record.view.state = state;
            if state == State::Complete {
                record.view.completed_bytes = record.view.total_bytes;
            }
            Ok(())
        })
    }

    pub(crate) fn remember_user_transfer_receiver(
        &self,
        id: &str,
        receiver: &str,
        token: &str,
        expires_ms: u64,
        complete: bool,
    ) -> Result<(), PersistenceError> {
        let key = format!("{receiver}/{token}");
        self.update_user_transfer(id, |record| {
            if record.view.direction != Direction::Upload || record.view.state == State::Cancelled {
                return Err(invalid("upload is not admitted"));
            }
            let now = crate::conversation::now_ms();
            if complete {
                let receipt = record
                    .receivers
                    .get_mut(&key)
                    .ok_or_else(|| invalid("unknown receiver request"))?;
                if receipt.expires_ms < now {
                    return Err(invalid("receiver request expired"));
                }
                receipt.complete = true;
                if record
                    .receivers
                    .values()
                    .filter(|value| value.expires_ms >= now)
                    .all(|value| value.complete)
                {
                    record.view.state = State::Complete;
                    record.view.completed_bytes = record.view.total_bytes;
                }
            } else {
                record.receivers.retain(|_, value| value.expires_ms >= now);
                if record.receivers.len() >= 64 && !record.receivers.contains_key(&key) {
                    return Err(invalid("too many simultaneous transfer receivers"));
                }
                record.receivers.insert(
                    key,
                    types::Receiver {
                        expires_ms,
                        complete: false,
                    },
                );
            }
            Ok(())
        })
    }

    pub(crate) fn record_user_upload_progress(
        &self,
        id: &str,
        bytes: u64,
        complete: bool,
    ) -> Result<(), PersistenceError> {
        self.update_user_transfer(id, |record| {
            if record.view.direction != Direction::Upload || record.view.state == State::Cancelled {
                return Err(invalid("upload is not admitted"));
            }
            record.view.completed_bytes = bytes.min(record.view.total_bytes);
            record.view.state = if complete {
                State::Complete
            } else {
                State::Running
            };
            Ok(())
        })
    }

    fn update_user_transfer(
        &self,
        id: &str,
        update: impl FnOnce(&mut TransferRecord) -> Result<(), PersistenceError>,
    ) -> Result<(), PersistenceError> {
        let key = key(id)?;
        self.write(|tx| {
            let mut record: TransferRecord = self
                .background_tx_row(tx, &key)?
                .ok_or_else(|| invalid("unknown user attachment admission"))?;
            let previous = encode(&record)?;
            update(&mut record)?;
            if encode(&record)? == previous {
                return Ok(());
            }
            record.view.revision = record
                .view
                .revision
                .checked_add(1)
                .ok_or_else(|| invalid("transfer revision exhausted"))?;
            Self::update_row(
                tx,
                BACKGROUND_DELIVERY,
                &key,
                Some(&encrypt_blob(&self.dek, &encode(&record)?)?),
            )?;
            self.write_current_transfer(tx, &record.view)
        })?;
        crate::api::background::background_delivery_changed();
        Ok(())
    }
}

fn key(id: &str) -> Result<String, PersistenceError> {
    let suffix = id
        .strip_prefix("transfer-")
        .ok_or_else(|| invalid("invalid transfer identity"))?;
    if suffix.len() != 32
        || !suffix
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        return Err(invalid("invalid transfer identity"));
    }
    Ok(format!("{PREFIX}{suffix}"))
}

fn invalid(message: &str) -> PersistenceError {
    PersistenceError::Json(message.into())
}

#[cfg(test)]
mod tests;
