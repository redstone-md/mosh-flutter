use crate::conversation::{message_log::ConversationMessage, transfer::Transfer};
use sha2::{Digest, Sha256};

/// Correlation survives erasure and excludes installation-specific attachment
/// row ids. Legacy channel manifests distinguish sends of identical content.
pub(crate) fn target<M: ConversationMessage>(
    context: &str,
    message: &M,
    transfer: &Transfer,
) -> Result<(String, bool), String> {
    if let Some(key) = message.metadata().and_then(|m| m.deletion_key.clone()) {
        return Ok((key, message.metadata().is_some_and(|m| m.local_only)));
    }
    if let Some(origin) = message.metadata().and_then(|m| m.origin.as_ref()) {
        return Ok((origin.key()?, false));
    }
    let (value, local_only) = if let Some(attachment) = message.attachment() {
        if !context.starts_with("channel:") {
            (
                serde_json::json!([
                    context,
                    "attachment",
                    attachment.attachment_id,
                    attachment.content_hash
                ]),
                false,
            )
        } else if let Some(manifest) = transfer.manifest_for(&attachment.attachment_id) {
            let bytes = super::MessageOrigin::manifest_bytes(&manifest)?;
            (
                serde_json::json!([context, "manifest", hex::encode(Sha256::digest(bytes))]),
                false,
            )
        } else {
            (
                serde_json::json!([
                    context,
                    "local",
                    message.message_id(),
                    message.sent_at_ms(),
                    message.author(),
                    attachment
                ]),
                true,
            )
        }
    } else if let Some(call_id) = message.call_id() {
        (serde_json::json!([context, "call", call_id]), false)
    } else if message.is_service() && message.message_id().is_some() {
        (
            serde_json::json!([context, "service", message.message_id()]),
            false,
        )
    } else {
        (
            serde_json::json!([
                context,
                "text",
                message.message_id(),
                message.sent_at_ms(),
                message.author(),
                message.body()
            ]),
            true,
        )
    };
    let bytes = serde_json::to_vec(&value).map_err(|e| e.to_string())?;
    Ok((hex::encode(Sha256::digest(bytes)), local_only))
}
