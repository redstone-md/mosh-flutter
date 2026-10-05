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
        attachment_target(context, message, transfer, attachment)?
    } else if let Some(call_id) = message.call_id() {
        (serde_json::json!([context, "call", call_id]), false)
    } else if message.is_service() && message.message_id().is_some() {
        (
            serde_json::json!([context, "service", message.message_id()]),
            false,
        )
    } else {
        return Ok((legacy_text_key(context, message)?, true));
    };
    let bytes = serde_json::to_vec(&value).map_err(|e| e.to_string())?;
    Ok((hex::encode(Sha256::digest(bytes)), local_only))
}

fn attachment_target<M: ConversationMessage>(
    context: &str,
    message: &M,
    transfer: &Transfer,
    attachment: &crate::conversation::attachments::AttachmentDescriptor,
) -> Result<(serde_json::Value, bool), String> {
    if !context.starts_with("channel:") {
        return Ok((
            serde_json::json!([
                context,
                "attachment",
                attachment.attachment_id,
                attachment.content_hash
            ]),
            false,
        ));
    }
    if let Some(manifest) = transfer.manifest_for(&attachment.attachment_id) {
        let bytes = super::MessageOrigin::manifest_bytes(&manifest)?;
        return Ok((
            serde_json::json!([context, "manifest", hex::encode(Sha256::digest(bytes))]),
            false,
        ));
    }
    Ok((
        serde_json::json!([
            context,
            "local",
            message.message_id(),
            message.sent_at_ms(),
            message.author(),
            attachment
        ]),
        true,
    ))
}

fn legacy_text_key<M: ConversationMessage>(context: &str, message: &M) -> Result<String, String> {
    super::correlation::text_key(context, message)?.ok_or_else(|| "missing text target".into())
}

/// Only the authenticated own-device history import/export calls this: both
/// copies carry the same frozen occurrence, without inventing author proofs.
pub(crate) fn correlate_history_text<M: ConversationMessage>(
    context: &str,
    message: &mut M,
) -> Result<(), String> {
    if let Some(origin) = message.metadata().and_then(|m| m.origin.as_ref()) {
        let key = origin.key()?;
        let metadata = message.metadata_mut().as_mut().unwrap();
        metadata.deletion_key = Some(key);
        metadata.local_only = false;
        return Ok(());
    }
    if message.metadata().is_some_and(|m| m.deletion.is_some()) {
        return Ok(());
    }
    let key = legacy_text_key(context, message)?;
    let metadata = message.metadata_mut().get_or_insert_with(Default::default);
    metadata.deletion_key = Some(key);
    metadata.local_only = false;
    Ok(())
}
