//! Exact personal correlation across authenticated own-device copies.
use crate::conversation::{message_log::ConversationMessage, transfer::Transfer};
use sha2::{Digest, Sha256};

struct TextCorrelation<'a> {
    id: Option<&'a str>,
    sent_at: Option<u64>,
    author: &'a str,
    content_hash: String,
}

impl TextCorrelation<'_> {
    fn key(&self, context: &str) -> Result<String, String> {
        let bytes = serde_json::to_vec(&(
            context,
            "text",
            self.id,
            self.sent_at,
            self.author,
            &self.content_hash,
        ))
        .map_err(|e| e.to_string())?;
        Ok(hex::encode(Sha256::digest(bytes)))
    }
}

pub(crate) fn message_key<M: ConversationMessage>(
    context: &str,
    message: &M,
    transfer: &Transfer,
) -> Result<Option<String>, String> {
    if let Some(key) = message
        .metadata()
        .and_then(|m| m.personal_correlation.clone())
    {
        return Ok(Some(key));
    }
    if message.attachment().is_some() {
        let mut legacy = message.clone();
        *legacy.metadata_mut() = None;
        let (key, local_only) = super::target::target(context, &legacy, transfer)?;
        return Ok((!local_only).then_some(key));
    }
    text_key(context, message)
}

pub(crate) fn history_message_key(context: &str, row: &serde_json::Value) -> Option<String> {
    let message = row.get("message")?;
    let metadata = message.get("metadata");
    if metadata
        .and_then(|m| m.get("deletion"))
        .is_some_and(|v| !v.is_null())
    {
        if let Some(key) = metadata
            .and_then(|m| m.get("personal_correlation"))
            .and_then(|v| v.as_str())
        {
            return Some(key.into());
        }
    }
    if let Some(descriptor) = message.get("attachment").filter(|v| !v.is_null()) {
        return history_attachment_key(context, descriptor, row.get("attachment_manifest"));
    }
    history_text_key(context, message)
}

fn history_attachment_key(
    context: &str,
    descriptor: &serde_json::Value,
    manifest: Option<&serde_json::Value>,
) -> Option<String> {
    let descriptor: crate::conversation::attachments::AttachmentDescriptor =
        serde_json::from_value(descriptor.clone()).ok()?;
    let target = if context.starts_with("channel:") {
        let manifest: crate::attachment_runtime::AttachmentManifest =
            serde_json::from_value(manifest?.clone()).ok()?;
        let bytes = super::MessageOrigin::manifest_bytes(&manifest).ok()?;
        serde_json::json!([context, "manifest", hex::encode(Sha256::digest(bytes))])
    } else {
        serde_json::json!([
            context,
            "attachment",
            descriptor.attachment_id,
            descriptor.content_hash
        ])
    };
    Some(hex::encode(Sha256::digest(
        serde_json::to_vec(&target).ok()?,
    )))
}

pub(crate) fn text_key<M: ConversationMessage>(
    context: &str,
    message: &M,
) -> Result<Option<String>, String> {
    if message.attachment().is_some() || message.call_id().is_some() || message.is_service() {
        return Ok(None);
    }
    let metadata = message.metadata();
    if metadata.is_some_and(|m| m.deletion.is_some() && m.origin.is_none()) {
        return Ok(metadata.and_then(|m| m.deletion_key.clone()));
    }
    TextCorrelation {
        id: message.message_id(),
        sent_at: message.sent_at_ms(),
        author: message.author(),
        content_hash: metadata.and_then(|m| m.origin.as_ref()).map_or_else(
            || hex::encode(Sha256::digest(message.body())),
            |o| o.content_hash.clone(),
        ),
    }
    .key(context)
    .map(Some)
}

pub(crate) fn history_text_key(context: &str, message: &serde_json::Value) -> Option<String> {
    if ["attachment", "call_event", "name_change"]
        .iter()
        .any(|key| message.get(key).is_some_and(|v| !v.is_null()))
    {
        return None;
    }
    let metadata = message.get("metadata");
    let origin = metadata
        .and_then(|m| m.get("origin"))
        .and_then(|v| serde_json::from_value::<super::MessageOrigin>(v.clone()).ok())
        .filter(|o| o.conversation == context && o.verify_signature().is_ok());
    if origin.is_none()
        && metadata
            .and_then(|m| m.get("deletion"))
            .is_some_and(|v| !v.is_null())
    {
        return metadata
            .and_then(|m| m.get("deletion_key"))
            .and_then(|v| v.as_str())
            .map(str::to_owned);
    }
    TextCorrelation {
        id: message.get("message_id").and_then(|v| v.as_str()),
        sent_at: message.get("sent_at_ms").and_then(|v| v.as_u64()),
        author: message
            .get(if context.starts_with("dm:") {
                "from_device"
            } else {
                "from_fingerprint"
            })
            .or_else(|| message.get("from"))?
            .as_str()?,
        content_hash: origin.map_or_else(
            || {
                message
                    .get("body")
                    .and_then(|v| v.as_str())
                    .map(|v| hex::encode(Sha256::digest(v)))
            },
            |o| Some(o.content_hash),
        )?,
    }
    .key(context)
    .ok()
}
