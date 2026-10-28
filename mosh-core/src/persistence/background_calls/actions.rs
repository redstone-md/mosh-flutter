use super::*;

impl Persistence {
    pub(crate) fn background_call_for_capability(
        &self,
        capability: &str,
        owner: &str,
    ) -> Result<Option<BackgroundCallState>, PersistenceError> {
        if capability.len() != 64 {
            return Ok(None);
        }
        let tx = self.db.begin_read().map_err(db_error)?;
        let rows = tx.open_table(BACKGROUND_DELIVERY).map_err(db_error)?;
        for row in rows.range(PREFIX.."call0").map_err(db_error)? {
            let (_, bytes) = row.map_err(db_error)?;
            let record: CallRecord = decode(&decrypt_blob(&self.dek, bytes.value())?)?;
            if record.owner == owner
                && [
                    record.answer.as_deref(),
                    record.decline.as_deref(),
                    record.hangup.as_deref(),
                ]
                .contains(&Some(capability))
            {
                return Ok(Some(record.state));
            }
        }
        Ok(None)
    }

    /// Caller holds the existing native runtime lock and supplies its current
    /// authenticated call. Possession of a call ID never grants action rights.
    pub(crate) fn take_background_call_action(
        &self,
        capability: &str,
        owner: &str,
        current: &BackgroundCallState,
        now: u64,
    ) -> Result<Option<BackgroundCallAction>, PersistenceError> {
        if capability.len() != 64
            || !capability
                .bytes()
                .all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())
        {
            return Ok(None);
        }
        let action = self.write(|tx| {
            let key = call_key(current);
            let Some(mut record) = self.background_tx_row::<CallRecord>(tx, &key)? else {
                return Ok(None);
            };
            if record.owner != owner
                || record.state != *current
                || (record.state.expires_at_ms != 0 && now >= record.state.expires_at_ms)
            {
                return Ok(None);
            }
            let action = if record.answer.as_deref() == Some(capability) {
                Some(BackgroundCallAction::Answer)
            } else if record.decline.as_deref() == Some(capability) {
                Some(BackgroundCallAction::Decline)
            } else if record.hangup.as_deref() == Some(capability) {
                Some(BackgroundCallAction::Hangup)
            } else {
                None
            };
            if action.is_some() {
                // Consume and replace together. A refused call control or
                // permission dialog keeps fresh buttons without replaying any
                // spent capability, even across an interrupted second write.
                record.replace(owner, current.clone())?;
                let bytes = encrypt_blob(&self.dek, &encode(&record)?)?;
                Self::update_row(tx, BACKGROUND_DELIVERY, &key, Some(&bytes))?;
            }
            Ok(action)
        })?;
        if action.is_some() {
            crate::api::background::background_delivery_changed();
        }
        Ok(action)
    }
}
