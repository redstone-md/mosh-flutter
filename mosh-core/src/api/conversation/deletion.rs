use super::{BridgeConversationKind, BridgeConversationRef};
use crate::api::conversation_bridge::ConversationBridgeError;
pub use crate::message_deletion::{types::DeleteMessagesResult, DeleteScope};

/// Validate the entire selection and durably apply one explicit deletion scope.
pub fn delete_messages(
    reference: BridgeConversationRef,
    message_ids: Vec<String>,
    scope: DeleteScope,
) -> Result<DeleteMessagesResult, ConversationBridgeError> {
    match reference.kind {
        BridgeConversationKind::Dm => super::super::private_dm::ensure_runtime()?
            .delete_messages(&reference.id, &message_ids, scope)
            .map_err(Into::into),
        BridgeConversationKind::Group => super::super::private_group::ensure_runtime()?
            .delete_messages(&reference.id, &message_ids, scope)
            .map_err(Into::into),
        BridgeConversationKind::Channel => super::super::channel::ensure_runtime()?
            .delete_messages(&reference.id, &message_ids, scope)
            .map_err(Into::into),
    }
}
