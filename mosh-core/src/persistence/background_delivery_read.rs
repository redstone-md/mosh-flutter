//! Reads reuse the current encrypted history row; no second plaintext copy.
use super::*;

impl Persistence {
    pub(crate) fn pending_background_notifications(
        &self,
        limit: u32,
    ) -> Result<Vec<BackgroundNotification>, PersistenceError> {
        let limit = usize::try_from(limit.min(16)).unwrap_or(16);
        if limit == 0 {
            return Ok(Vec::new());
        }
        let tx = self.db.begin_read().map_err(db_error)?;
        let rows = tx.open_table(BACKGROUND_DELIVERY).map_err(db_error)?;
        let mut pending = Vec::new();
        for row in rows.range(MESSAGE_PREFIX.."message0").map_err(db_error)? {
            let (_, bytes) = row.map_err(db_error)?;
            let summary: Summary = decode(&decrypt_blob(&self.dek, bytes.value())?)?;
            if !summary.acknowledged {
                if let Some(notification) = self.background_notification(&tx, summary)? {
                    pending.push(notification);
                }
            }
            if pending.len() == limit {
                break;
            }
        }
        Ok(pending)
    }

    pub(crate) fn ack_background_notification(
        &self,
        id: &str,
        revision: u64,
    ) -> Result<(), PersistenceError> {
        if id.is_empty() || id.len() > 128 {
            return Err(PersistenceError::Json(
                "invalid background notification id".into(),
            ));
        }
        self.write(|tx| {
            let mut update = None;
            let rows = tx.open_table(BACKGROUND_DELIVERY).map_err(db_error)?;
            for row in rows.range(MESSAGE_PREFIX.."message0").map_err(db_error)? {
                let (key, bytes) = row.map_err(db_error)?;
                let mut summary: Summary = decode(&decrypt_blob(&self.dek, bytes.value())?)?;
                if summary.id == id && summary.revision == revision {
                    summary.acknowledged = true;
                    update = Some((
                        key.value().to_string(),
                        encrypt_blob(&self.dek, &encode(&summary)?)?,
                    ));
                    break;
                }
            }
            drop(rows);
            if let Some((key, blob)) = update {
                Self::update_row(tx, BACKGROUND_DELIVERY, &key, Some(&blob))?;
            }
            Ok(())
        })
    }

    fn background_notification(
        &self,
        tx: &redb::ReadTransaction,
        summary: Summary,
    ) -> Result<Option<BackgroundNotification>, PersistenceError> {
        let tables = match summary.target.kind {
            BridgeConversationKind::Dm => DM_HISTORY,
            BridgeConversationKind::Group => GROUP_HISTORY,
            BridgeConversationKind::Channel => CHANNEL_HISTORY,
        };
        let key =
            Self::history_message_key(&summary.target.id, summary.sent_at_ms, &summary.message_id);
        let rows = tx.open_table(tables.messages).map_err(db_error)?;
        let Some(row) = rows.get(key.as_str()).map_err(db_error)? else {
            return Ok(None);
        };
        let value: serde_json::Value = decode(&decrypt_blob(&self.dek, row.value())?)?;
        if value
            .pointer("/message/metadata/deletion")
            .is_some_and(|value| !value.is_null())
        {
            return Ok(None);
        }
        let text = value
            .pointer("/message/body")
            .and_then(|value| value.as_str());
        let sender = value
            .pointer("/message/from_device")
            .or_else(|| value.pointer("/message/from_fingerprint"))
            .and_then(|value| value.as_str());
        Ok(Some(BackgroundNotification {
            id: summary.id,
            revision: summary.revision,
            target: summary.target,
            occurrence_id: summary.occurrence_id,
            sent_at_ms: summary.sent_at_ms,
            message_count: summary.message_count,
            sender: bounded(sender, 256),
            text: bounded(text, 8192),
        }))
    }
}

fn bounded(value: Option<&str>, length: usize) -> Option<String> {
    value.map(|value| value.chars().take(length).collect())
}
