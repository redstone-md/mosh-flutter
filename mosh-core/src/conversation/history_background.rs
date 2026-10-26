//! Durable notification facts for already-authenticated incoming DM rows.
use super::*;

pub(super) fn message<M: ConversationMessage>(
    tables: HistoryTables,
    conversation_id: &str,
    sent_at_ms: u64,
    message_id: &str,
    message: &M,
) -> Option<crate::persistence::BackgroundMessageAdmission> {
    let metadata = message.metadata()?;
    if tables.outbound_scope != "private_dm"
        || metadata.is_own != Some(false)
        || message.is_service()
        || metadata.deletion.is_some()
    {
        return None;
    }
    let occurrence_id = metadata
        .origin
        .as_ref()
        .map(|origin| format!("{}/{}", origin.author, origin.id))
        .unwrap_or_else(|| message_id.to_string());
    Some(crate::persistence::BackgroundMessageAdmission {
        tables,
        conversation_id: conversation_id.to_string(),
        occurrence_id,
        message_id: message_id.to_string(),
        sent_at_ms,
    })
}
