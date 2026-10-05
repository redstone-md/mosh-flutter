use super::{authority::DeletionAuthority, target, DeletionBook};
use crate::conversation::{
    message_log::{ConversationMessage, MessageLog},
    transfer::Transfer,
};

pub(crate) fn messages<M: ConversationMessage>(
    log: &MessageLog<M>,
    transfer: &Transfer,
    book: &DeletionBook,
    authority: Option<&DeletionAuthority>,
) -> Vec<M> {
    log.visible()
        .into_iter()
        .map(|mut message| {
            let service = message.is_service();
            let local_only =
                target::target(&book.context, &message, transfer).map_or(true, |(_, local)| local);
            let metadata = message.metadata_mut().get_or_insert_with(Default::default);
            metadata.local_only = local_only;
            metadata.can_delete_for_everyone = !service
                && metadata.deletion.is_none()
                && book.store.is_some()
                && metadata.origin.as_ref().is_some_and(|o| {
                    o.conversation == book.context
                        && o.verify_signature().is_ok()
                        && authority.is_some_and(|a| a.permitted(o).is_some())
                });
            if let Some(origin) = &metadata.origin {
                metadata.is_own = authority.map(|a| a.is_author(origin));
            }
            message
        })
        .collect()
}
