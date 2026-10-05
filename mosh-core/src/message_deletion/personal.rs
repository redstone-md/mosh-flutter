use super::{
    book::validate_selection, types::DeleteMessagesResult, DeleteScope, DeletionContext,
    DeletionError, DeletionRecord, DeletionStatus,
};
use crate::conversation::message_log::ConversationMessage;

pub(crate) fn delete_for_me<M: ConversationMessage>(
    context: &mut DeletionContext<'_, M>,
    ids: &[String],
    peer: Option<&str>,
) -> Result<DeleteMessagesResult, DeletionError> {
    if let (Some(store), Some(peer)) = (&context.book.store, peer) {
        crate::device_link::identity::DeviceIdentity::open(store.clone(), peer)
            .map_err(|e| DeletionError::Persistence(e.to_string()))?;
    }
    context.book.reload().map_err(DeletionError::Persistence)?;
    let ids = validate_selection(context.log, ids)?;
    let owner = context.book.user()?;
    let mut records = Vec::new();
    for message in context
        .log
        .iter()
        .filter(|m| m.message_id().is_some_and(|id| ids.contains(id)))
    {
        let (key, local_only) =
            super::target::target(&context.book.context, message, context.transfer)
                .map_err(DeletionError::Internal)?;
        records.push(DeletionRecord {
            personal_correlation: super::correlation::message_key(
                &context.book.context,
                message,
                context.transfer,
            )
            .map_err(DeletionError::Internal)?
            .filter(|alias| alias != &key),
            context: context.book.context.clone(),
            key,
            scope: DeleteScope::ForMe,
            owner: owner.clone(),
            local_only,
            status: DeletionStatus::Confirmed,
            administrator: None,
            request: None,
            acknowledgement: None,
        });
    }
    let result = DeleteMessagesResult {
        deleted_count: records.len(),
        local_only_count: records.iter().filter(|r| r.local_only).count(),
        pending_count: 0,
    };
    super::application::install(context, &records, false).map_err(DeletionError::Persistence)?;
    Ok(result)
}
