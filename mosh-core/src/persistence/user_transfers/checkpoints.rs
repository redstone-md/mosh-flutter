//! Only already authenticated chunk frames enter a transfer checkpoint.
use super::*;
use crate::attachment_runtime::ChunkFrame;

impl Persistence {
    #[cfg(test)]
    pub(crate) fn save_user_transfer_chunk(
        &self,
        id: &str,
        frame: &ChunkFrame,
    ) -> Result<(), PersistenceError> {
        self.save_user_transfer_chunks(id, std::slice::from_ref(frame))
    }

    pub(crate) fn save_user_transfer_chunks(
        &self,
        id: &str,
        frames: &[ChunkFrame],
    ) -> Result<(), PersistenceError> {
        let record_key = key(id)?;
        self.write(|tx| {
            let mut record: TransferRecord = self
                .background_tx_row(tx, &record_key)?
                .ok_or_else(|| invalid("unknown user transfer checkpoint"))?;
            let manifest = record
                .manifest
                .as_ref()
                .ok_or_else(|| invalid("unbound user transfer"))?;
            if record.view.direction != Direction::Download
                || matches!(record.view.state, State::Cancelled | State::Complete)
            {
                return Err(invalid("invalid user transfer chunk binding"));
            }
            let mut added = 0;
            for frame in frames {
                if manifest.attachment_id != frame.attachment_id
                    || frame.chunk_index >= manifest.chunk_count
                {
                    return Err(invalid("invalid user transfer chunk binding"));
                }
                let chunk_key = chunk_key(id, frame.chunk_index)?;
                if self
                    .background_tx_row::<ChunkFrame>(tx, &chunk_key)?
                    .is_some()
                {
                    continue;
                }
                added += u64::from(manifest.chunk_size)
                    .min(manifest.total_size - frame.chunk_index * u64::from(manifest.chunk_size));
                Self::update_row(
                    tx,
                    BACKGROUND_DELIVERY,
                    &chunk_key,
                    Some(&encrypt_blob(&self.dek, &encode(frame)?)?),
                )?;
            }
            if added == 0 {
                return Ok(());
            }
            record.view.completed_bytes = record
                .view
                .completed_bytes
                .saturating_add(added)
                .min(record.view.total_bytes);
            record.view.revision = record
                .view
                .revision
                .checked_add(1)
                .ok_or_else(|| invalid("transfer revision exhausted"))?;
            Self::update_row(
                tx,
                BACKGROUND_DELIVERY,
                &record_key,
                Some(&encrypt_blob(&self.dek, &encode(&record)?)?),
            )?;
            self.write_current_transfer(tx, &record.view)
        })?;
        crate::api::background::background_delivery_changed();
        Ok(())
    }

    pub(crate) fn user_transfer_chunks(
        &self,
        id: &str,
    ) -> Result<Vec<ChunkFrame>, PersistenceError> {
        key(id)?;
        let prefix = format!("transfer-chunk/{id}/");
        let end = format!("transfer-chunk/{id}0");
        let tx = self.db.begin_read().map_err(db_error)?;
        let rows = tx.open_table(BACKGROUND_DELIVERY).map_err(db_error)?;
        rows.range(prefix.as_str()..end.as_str())
            .map_err(db_error)?
            .map(|row| {
                let (_, value) = row.map_err(db_error)?;
                decode(&decrypt_blob(&self.dek, value.value())?)
            })
            .collect()
    }
}

fn chunk_key(id: &str, index: u64) -> Result<String, PersistenceError> {
    key(id)?;
    Ok(format!("transfer-chunk/{id}/{index:016x}"))
}

impl Persistence {
    pub(crate) fn remove_user_transfer(&self, id: &str) -> Result<(), PersistenceError> {
        let record_key = key(id)?;
        let prefix = format!("transfer-chunk/{id}/");
        let end = format!("transfer-chunk/{id}0");
        self.write(|tx| {
            let keys: Vec<_> = {
                let rows = tx.open_table(BACKGROUND_DELIVERY).map_err(db_error)?;
                rows.range(prefix.as_str()..end.as_str())
                    .map_err(db_error)?
                    .map(|row| {
                        let (key, _) = row.map_err(db_error)?;
                        Ok(key.value().to_owned())
                    })
                    .collect::<Result<_, PersistenceError>>()?
            };
            for key in keys {
                Self::update_row(tx, BACKGROUND_DELIVERY, &key, None)?;
            }
            Self::update_row(tx, BACKGROUND_DELIVERY, &record_key, None)?;
            Self::remove_current_transfer(tx, id)
        })?;
        crate::api::background::background_delivery_changed();
        Ok(())
    }
}

impl Persistence {
    pub(in crate::persistence) fn delete_conversation_transfers(
        &self,
        tx: &redb::WriteTransaction,
        tables: HistoryTables,
        id: &str,
    ) -> Result<(), PersistenceError> {
        use crate::api::conversation::BridgeConversationKind as Kind;
        let kind = match tables.outbound_scope {
            "private_dm" => Kind::Dm,
            "private_group" => Kind::Group,
            _ => Kind::Channel,
        };
        let ids = {
            let rows = tx.open_table(BACKGROUND_DELIVERY).map_err(db_error)?;
            let mut ids = Vec::new();
            for row in rows.range(PREFIX.."transfer0").map_err(db_error)? {
                let (_, bytes) = row.map_err(db_error)?;
                let record: TransferRecord = decode(&decrypt_blob(&self.dek, bytes.value())?)?;
                if record.view.target.kind == kind && record.view.target.id == id {
                    ids.push(record.view.id);
                }
            }
            ids
        };
        for id in ids {
            Self::update_row(tx, BACKGROUND_DELIVERY, &key(&id)?, None)?;
            Self::remove_current_transfer(tx, &id)?;
            let prefix = format!("transfer-chunk/{id}/");
            let end = format!("transfer-chunk/{id}0");
            tx.open_table(BACKGROUND_DELIVERY)
                .map_err(db_error)?
                .retain_in(prefix.as_str()..end.as_str(), |_, _| false)
                .map_err(db_error)?;
        }
        Ok(())
    }
}
