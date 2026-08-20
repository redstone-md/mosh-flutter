//! A stand-in message for the tests of the shared conversation code.
//!
//! The real message types drag in a runtime each. This one carries only what
//! [`ConversationMessage`] asks for, so a test can prove the shared code
//! without booting a DM, a group or a channel.

use serde::{Deserialize, Serialize};

use super::message_log::ConversationMessage;
use crate::outbound_delivery::{MessageDeliveryMeta, MessageDeliveryStatus};
use crate::private_dm_runtime::AttachmentDescriptor;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct TestMessage {
    pub from: String,
    pub body: String,
    pub message_id: Option<String>,
    pub sent_at_ms: Option<u64>,
    pub delivery_status: Option<MessageDeliveryStatus>,
    pub delivery_error: Option<String>,
    pub retryable: Option<bool>,
    pub retry_count: Option<u32>,
}

impl TestMessage {
    pub fn new(from: &str, body: &str) -> Self {
        Self {
            from: from.to_string(),
            body: body.to_string(),
            message_id: None,
            sent_at_ms: None,
            delivery_status: None,
            delivery_error: None,
            retryable: None,
            retry_count: None,
        }
    }

    pub fn at(mut self, sent_at_ms: u64) -> Self {
        self.sent_at_ms = Some(sent_at_ms);
        self
    }

    pub fn with_id(mut self, message_id: &str) -> Self {
        self.message_id = Some(message_id.to_string());
        self
    }
}

impl ConversationMessage for TestMessage {
    fn message_id(&self) -> Option<&str> {
        self.message_id.as_deref()
    }

    fn set_message_id(&mut self, message_id: String) {
        self.message_id = Some(message_id);
    }

    fn sent_at_ms(&self) -> Option<u64> {
        self.sent_at_ms
    }

    fn set_sent_at_ms(&mut self, sent_at_ms: u64) {
        self.sent_at_ms = Some(sent_at_ms);
    }

    fn body(&self) -> &str {
        &self.body
    }

    fn author(&self) -> &str {
        &self.from
    }

    /// Nothing here carries a file: the attachment paths have their own tests.
    fn attachment(&self) -> Option<&AttachmentDescriptor> {
        None
    }

    fn set_delivery(&mut self, delivery: MessageDeliveryMeta) {
        self.delivery_status = delivery.delivery_status;
        self.delivery_error = delivery.delivery_error;
        self.retryable = delivery.retryable;
        self.retry_count = delivery.retry_count;
    }
}
