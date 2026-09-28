use super::super::{invalid, types::Result};
use crate::private_dm_runtime::ChatMessage;
use serde::{Deserialize, Serialize};

/// Semantic text only. No keys, MLS state, attachments or local send attempts.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::private_dm_runtime) struct TextRecord {
    pub message_id: String,
    pub sent_at_ms: u64,
    pub from_device: String,
    pub body: String,
}

impl TextRecord {
    pub fn from_message(message: &ChatMessage) -> Option<Self> {
        if message.attachment.is_some() || message.call_event.is_some() {
            return None;
        }
        Some(Self {
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

    pub fn into_message(self) -> ChatMessage {
        ChatMessage {
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
