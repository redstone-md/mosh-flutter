use super::*;
use crate::message_deletion::{DeleteScope, DeletionRecord};

impl Persistence {
    pub(super) fn erase_known_target(
        &self,
        tx: &redb::WriteTransaction,
        tables: HistoryTables,
        bytes: &[u8],
    ) -> Result<Vec<u8>, PersistenceError> {
        let Ok(mut value) = serde_json::from_slice::<serde_json::Value>(bytes) else {
            return Ok(bytes.to_vec());
        };
        let kind = match tables.outbound_scope {
            "private_dm" => "dm",
            "private_group" => "group",
            _ => "channel",
        };
        let Some(id) = value.get("conversation_id").and_then(|v| v.as_str()) else {
            return Ok(bytes.to_vec());
        };
        let context = format!("{kind}:{id}");
        let correlation =
            crate::message_deletion::correlation::history_message_key(&context, &value);
        let Some(target) = history_target(value.pointer("/message/metadata"), &context)
            .or_else(|| correlation.clone())
        else {
            return Ok(bytes.to_vec());
        };
        let owner = self.deletion_owner(tx)?;
        let Some(record) =
            self.matching_deletion(tx, &context, &target, correlation.as_deref(), &owner)?
        else {
            return Ok(bytes.to_vec());
        };
        if let Some(attachment) = value
            .pointer("/message/attachment")
            .filter(|v| !v.is_null())
        {
            let descriptor = serde_json::from_value(attachment.clone())
                .map_err(|e| PersistenceError::Json(e.to_string()))?;
            self.enqueue_attachment_gc(tx, &descriptor)?;
        }
        erase_content(&mut value, &record, &target, correlation.as_deref())?;
        serde_json::to_vec(&value).map_err(|e| PersistenceError::Json(e.to_string()))
    }

    fn deletion_owner(&self, tx: &redb::WriteTransaction) -> Result<String, PersistenceError> {
        let table = tx.open_table(DEVICE_LINK).map_err(db_error)?;
        let Some(row) = table.get(DEVICE_LINK_KEY).map_err(db_error)? else {
            return Ok("local".into());
        };
        let identity: crate::device_link::identity::LocalIdentity =
            serde_json::from_slice(&decrypt_blob(&self.dek, row.value())?)
                .map_err(|e| PersistenceError::Json(e.to_string()))?;
        Ok(identity.roster.user_id())
    }

    fn matching_deletion(
        &self,
        tx: &redb::WriteTransaction,
        context: &str,
        target: &str,
        personal_correlation: Option<&str>,
        owner: &str,
    ) -> Result<Option<DeletionRecord>, PersistenceError> {
        let mut matching = self.deletion_target_records(tx, context, target)?;
        if let Some(alias) = personal_correlation.filter(|alias| *alias != target) {
            matching.extend(self.deletion_target_records(tx, context, alias)?);
        }
        Ok(matching
            .into_iter()
            .filter(|record| {
                record.matches(target, personal_correlation)
                    && (record.scope == DeleteScope::ForEveryone || record.owner == owner)
            })
            .max_by_key(|r| {
                (
                    r.scope == DeleteScope::ForMe,
                    r.status == crate::message_deletion::DeletionStatus::Confirmed,
                    r.storage_key(),
                )
            }))
    }
}

fn history_target(metadata: Option<&serde_json::Value>, context: &str) -> Option<String> {
    metadata
        .and_then(|m| m.get("deletion_key"))
        .and_then(|v| v.as_str())
        .map(str::to_owned)
        .or_else(|| {
            metadata
                .and_then(|m| m.get("origin"))
                .and_then(|v| {
                    serde_json::from_value::<crate::message_deletion::MessageOrigin>(v.clone()).ok()
                })
                .filter(|o| o.conversation == context && o.verify_signature().is_ok())
                .and_then(|o| o.key().ok())
        })
}

fn erase_content(
    value: &mut serde_json::Value,
    record: &DeletionRecord,
    target: &str,
    correlation: Option<&str>,
) -> Result<(), PersistenceError> {
    let message = value
        .get_mut("message")
        .and_then(|v| v.as_object_mut())
        .ok_or_else(|| PersistenceError::Json("invalid history row".into()))?;
    for key in [
        "attachment",
        "call_event",
        "name_change",
        "delivery_status",
        "delivery_error",
        "retryable",
        "retry_count",
    ] {
        message.insert(key.into(), serde_json::Value::Null);
    }
    message.insert("body".into(), "".into());
    let metadata = message
        .entry("metadata")
        .or_insert_with(|| serde_json::json!({}));
    if !metadata.is_object() {
        *metadata = serde_json::json!({});
    }
    metadata["deletion_key"] = target.into();
    metadata["personal_correlation"] = correlation
        .filter(|alias| *alias != target)
        .map_or(serde_json::Value::Null, |alias| alias.into());
    metadata["deletion"] =
        serde_json::to_value(record.marker()).map_err(|e| PersistenceError::Json(e.to_string()))?;
    metadata["can_delete_for_everyone"] = false.into();
    value["attachment_manifest"] = serde_json::Value::Null;
    Ok(())
}
