//! Rename through the existing conversation and account runtime owners.
use super::{BridgeConversationKind, BridgeConversationRef};
use crate::api::conversation_bridge::{ConversationBridgeError, ConversationBridgeErrorKind};
pub use crate::chat_names::ChatNameSnapshot;

pub fn personal_names() -> Result<ChatNameSnapshot, ConversationBridgeError> {
    super::super::device_link::with_runtime(|rt| rt.chat_names_snapshot()).map_err(Into::into)
}

pub fn rename(
    reference: BridgeConversationRef,
    name: String,
) -> Result<(), ConversationBridgeError> {
    match reference.kind {
        BridgeConversationKind::Group => super::super::private_group::ensure_runtime()?
            .rename_group(&reference.id, &name)
            .map(|_| ())
            .map_err(Into::into),
        kind => super::super::device_link::with_runtime(|rt| {
            rt.rename_chat(&key(kind, &reference.id), &name)
        })
        .map(|_| ())
        .map_err(Into::into),
    }
}

pub fn reset_name(reference: BridgeConversationRef) -> Result<(), ConversationBridgeError> {
    if reference.kind == BridgeConversationKind::Group {
        return Err(ConversationBridgeError::new(
            ConversationBridgeErrorKind::InvalidInput,
            "a shared group name cannot be reset",
        ));
    }
    super::super::device_link::with_runtime(|rt| {
        rt.reset_chat_name(&key(reference.kind, &reference.id))
    })
    .map(|_| ())
    .map_err(Into::into)
}

fn key(kind: BridgeConversationKind, id: &str) -> String {
    format!(
        "{}:{id}",
        match kind {
            BridgeConversationKind::Dm => "dm",
            BridgeConversationKind::Channel => "channel",
            BridgeConversationKind::Group => "group",
        }
    )
}
