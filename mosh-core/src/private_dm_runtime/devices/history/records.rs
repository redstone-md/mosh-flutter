use super::super::{invalid, types::Result};
use crate::private_dm_runtime::ChatMessage;
use serde::{Deserialize, Serialize};

/// Semantic text only. No keys, MLS state, attachments or local send attempts.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::private_dm_runtime) struct TextRecord {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub metadata: Option<crate::message_deletion::MessageMetadata>,
    pub message_id: String,
    pub sent_at_ms: u64,
    pub from_device: String,
    pub body: String,
}

impl TextRecord {
    /// Does `incoming` describe this same message? A tombstone matches the
    /// live copy it erased: the body is gone, the identity is not. It carries
    /// no deletion authority, so the live copy stays until the deletion
    /// journal erases it (ADR 0040).
    pub(super) fn same_content(&self, incoming: &Self) -> bool {
        let origin = |record: &Self| record.metadata.as_ref().and_then(|m| m.origin.clone());
        self.message_id == incoming.message_id
            && self.sent_at_ms == incoming.sent_at_ms
            && self.from_device == incoming.from_device
            && (self.body == incoming.body || incoming.is_tombstone())
            && (origin(self).is_none()
                || origin(incoming).is_none()
                || origin(self) == origin(incoming))
    }

    fn is_tombstone(&self) -> bool {
        self.metadata.as_ref().is_some_and(|m| m.deletion.is_some())
    }
    pub fn from_message(message: &ChatMessage) -> Option<Self> {
        if message.attachment.is_some() || message.call_event.is_some() {
            return None;
        }
        Some(Self {
            metadata: message.metadata.clone(),
            message_id: message.message_id.clone()?,
            sent_at_ms: message.sent_at_ms?,
            from_device: message.from_device.clone(),
            body: message.body.clone(),
        })
    }

    pub fn validate(&self) -> Result<()> {
        if self.message_id.is_empty() || self.message_id.len() > 256 || self.from_device.is_empty()
        {
            return Err(invalid());
        }
        Ok(())
    }

    pub(super) fn validate_content(&self, context: &str) -> Result<()> {
        if let Some(origin) = self.metadata.as_ref().and_then(|m| m.origin.as_ref()) {
            if self.is_tombstone() {
                if origin.conversation != context
                    || origin.id != self.message_id
                    || !self.body.is_empty()
                {
                    return Err(invalid());
                }
                origin.verify_signature().map_err(|_| invalid())?;
            } else {
                origin
                    .verify(context, &self.message_id, self.body.as_bytes())
                    .map_err(|_| invalid())?;
            }
        }
        Ok(())
    }

    pub fn into_message(self) -> ChatMessage {
        ChatMessage {
            metadata: self.metadata,
            from_device: self.from_device,
            body: self.body,
            message_id: Some(self.message_id),
            sent_at_ms: Some(self.sent_at_ms),
            attachment: None,
            call_event: None,
            delivery_status: None,
            delivery_error: None,
            retryable: None,
            retry_count: None,
            read: None,
        }
    }
}
