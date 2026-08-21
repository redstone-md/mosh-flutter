//! The message list every conversation kind keeps.
//!
//! The three kinds hold different message types — a DM message carries call
//! events, a group message carries the sender's fingerprint — but they all do
//! the same things with them: stamp an id and a time on a new one, replace one
//! by id, spot a copy that already arrived, record what happened to a send.
//! That work lives here once, behind [`ConversationMessage`].
//!
//! The log derefs to a slice, so reading it (iterate, count, clone out for a
//! snapshot) works as if it were a plain `Vec`.

use std::ops::Deref;

use serde::Serialize;

use super::attachments::AttachmentDescriptor;
use super::now_ms;
use crate::message_id::MessageIdGen;
use crate::outbound_delivery::{MessageDeliveryMeta, MessageDeliveryStatus};

/// What a conversation runtime needs from a message to keep a log of them.
pub trait ConversationMessage: Clone + Serialize {
    fn message_id(&self) -> Option<&str>;
    fn set_message_id(&mut self, message_id: String);
    fn sent_at_ms(&self) -> Option<u64>;
    fn set_sent_at_ms(&mut self, sent_at_ms: u64);
    fn body(&self) -> &str;
    /// Who sent it, in whatever form this kind can tell senders apart by: the
    /// device fingerprint in a channel or a group, the device name in a DM
    /// (a DM message has no fingerprint field, and it only ever has two
    /// participants).
    fn author(&self) -> &str;
    /// The file this message carries, if it carries one.
    fn attachment(&self) -> Option<&AttachmentDescriptor>;
    fn set_delivery(&mut self, delivery: MessageDeliveryMeta);
    /// How this message's send last ended. What a restart reads to tell a
    /// finished send from one the process died in the middle of.
    fn delivery_status(&self) -> Option<MessageDeliveryStatus>;
}

/// Why a log lookup failed. Each runtime maps this onto its own error.
#[derive(Debug)]
pub enum LogError {
    Missing(String),
    Codec(String),
}

impl std::fmt::Display for LogError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Missing(id) => write!(formatter, "message missing: {id}"),
            Self::Codec(error) => write!(formatter, "{error}"),
        }
    }
}

impl std::error::Error for LogError {}

/// The messages of one conversation, oldest first, plus the id generator that
/// stamps the new ones.
pub struct MessageLog<M> {
    messages: Vec<M>,
    ids: MessageIdGen,
}

// Written out rather than derived: a derived `Default` would demand `M:
// Default`, which no message type has a use for.
impl<M> Default for MessageLog<M> {
    fn default() -> Self {
        Self {
            messages: Vec::new(),
            ids: MessageIdGen::default(),
        }
    }
}

impl<M> Deref for MessageLog<M> {
    type Target = [M];

    fn deref(&self) -> &[M] {
        &self.messages
    }
}

impl<M: ConversationMessage> MessageLog<M> {
    /// Gives a message its send time and, if it has none, an id. Ids come from
    /// a running counter, so two messages stamped in the same millisecond
    /// cannot collide.
    pub fn stamp(&self, mut message: M) -> M {
        let sent_at_ms = message.sent_at_ms().unwrap_or_else(now_ms);
        message.set_sent_at_ms(sent_at_ms);
        if message.message_id().unwrap_or_default().is_empty() {
            message.set_message_id(self.ids.next(sent_at_ms));
        }
        message
    }

    /// Appends a message that is already stamped.
    pub fn push(&mut self, message: M) {
        self.messages.push(message);
    }

    /// Stamps a message and appends it.
    pub fn push_stamped(&mut self, message: M) {
        let stamped = self.stamp(message);
        self.messages.push(stamped);
    }

    /// Replaces the message with the same id, or appends it.
    pub fn upsert(&mut self, message: M) {
        if let Some(message_id) = message.message_id() {
            if let Some(existing) = self
                .messages
                .iter_mut()
                .find(|existing| existing.message_id() == Some(message_id))
            {
                *existing = message;
                return;
            }
        }
        self.messages.push(message);
    }

    pub fn find_mut(&mut self, message_id: &str) -> Option<&mut M> {
        self.messages
            .iter_mut()
            .find(|message| message.message_id() == Some(message_id))
    }

    /// Whether this message is already in the log. Ids decide it when both
    /// sides have one; otherwise same sender, same time and same text counts
    /// as the same message.
    pub fn holds_copy_of(&self, candidate: &M) -> bool {
        self.messages.iter().any(|existing| {
            existing.author() == candidate.author()
                && match (existing.message_id(), candidate.message_id()) {
                    (Some(left), Some(right)) if !left.is_empty() && !right.is_empty() => {
                        left == right
                    }
                    _ => {
                        existing.sent_at_ms() == candidate.sent_at_ms()
                            && existing.body() == candidate.body()
                    }
                }
        })
    }

    /// Records how a send went. A failed send is the only one the user can
    /// retry, so that is the only one marked retryable.
    pub fn mark_delivery(
        &mut self,
        message_id: &str,
        status: MessageDeliveryStatus,
        error: Option<String>,
        retry_count: u32,
    ) -> Result<(), LogError> {
        let message = self
            .find_mut(message_id)
            .ok_or_else(|| LogError::Missing(message_id.to_string()))?;
        message.set_delivery(delivery_meta(status, error, retry_count));
        Ok(())
    }

    /// The message as JSON, for the outbound attempt record that survives a
    /// restart.
    pub fn json_for(&self, message_id: &str) -> Result<String, LogError> {
        let message = self
            .messages
            .iter()
            .find(|message| message.message_id() == Some(message_id))
            .ok_or_else(|| LogError::Missing(message_id.to_string()))?;
        serde_json::to_string(message).map_err(|error| LogError::Codec(error.to_string()))
    }
}

/// How a send went. A failed send is the only one the user can retry, so that
/// is the only one marked retryable. Used directly when a message is rebuilt
/// from a stored attempt and is not in the log yet.
pub fn delivery_meta(
    status: MessageDeliveryStatus,
    error: Option<String>,
    retry_count: u32,
) -> MessageDeliveryMeta {
    MessageDeliveryMeta {
        delivery_status: Some(status),
        delivery_error: error,
        retryable: Some(matches!(status, MessageDeliveryStatus::Failed)),
        retry_count: Some(retry_count),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::conversation::test_message::TestMessage;

    #[test]
    fn stamping_gives_every_message_its_own_id() {
        let log: MessageLog<TestMessage> = MessageLog::default();
        let first = log.stamp(TestMessage::new("alice", "one").at(1000));
        let second = log.stamp(TestMessage::new("alice", "two").at(1000));

        assert_eq!(first.sent_at_ms, Some(1000));
        assert_ne!(first.message_id, second.message_id);
    }

    #[test]
    fn stamping_keeps_an_id_the_message_already_has() {
        let log: MessageLog<TestMessage> = MessageLog::default();
        let stamped = log.stamp(TestMessage::new("alice", "one").at(1000).with_id("mine"));

        assert_eq!(stamped.message_id.as_deref(), Some("mine"));
    }

    #[test]
    fn upsert_replaces_by_id_instead_of_appending() {
        let mut log = MessageLog::default();
        log.push(TestMessage::new("alice", "draft").at(1).with_id("m1"));
        log.push(TestMessage::new("bob", "hello").at(2).with_id("m2"));

        log.upsert(TestMessage::new("alice", "final").at(1).with_id("m1"));

        assert_eq!(log.len(), 2);
        assert_eq!(log[0].body, "final");
        assert_eq!(log[1].body, "hello");
    }

    #[test]
    fn a_message_without_an_id_is_always_appended() {
        let mut log = MessageLog::default();
        log.upsert(TestMessage::new("alice", "one").at(1));
        log.upsert(TestMessage::new("alice", "two").at(2));

        assert_eq!(log.len(), 2);
    }

    #[test]
    fn a_copy_is_spotted_by_id_or_by_sender_time_and_text() {
        let mut log = MessageLog::default();
        log.push(TestMessage::new("alice", "hello").at(1).with_id("m1"));

        assert!(log.holds_copy_of(&TestMessage::new("alice", "different").at(9).with_id("m1")));
        assert!(log.holds_copy_of(&TestMessage::new("alice", "hello").at(1)));
        assert!(!log.holds_copy_of(&TestMessage::new("bob", "hello").at(1)));
        assert!(!log.holds_copy_of(&TestMessage::new("alice", "hello").at(2)));
    }

    #[test]
    fn only_a_failed_send_is_marked_retryable() {
        let mut log = MessageLog::default();
        log.push(TestMessage::new("alice", "hello").at(1).with_id("m1"));

        log.mark_delivery(
            "m1",
            MessageDeliveryStatus::Failed,
            Some("no route".to_string()),
            2,
        )
        .expect("failed mark");
        assert_eq!(log[0].retryable, Some(true));
        assert_eq!(log[0].delivery_error.as_deref(), Some("no route"));
        assert_eq!(log[0].retry_count, Some(2));

        log.mark_delivery("m1", MessageDeliveryStatus::Sent, None, 2)
            .expect("sent mark");
        assert_eq!(log[0].retryable, Some(false));
        assert_eq!(log[0].delivery_error, None);
    }

    #[test]
    fn a_missing_id_is_an_error_not_a_silent_no_op() {
        let mut log: MessageLog<TestMessage> = MessageLog::default();

        assert!(matches!(
            log.mark_delivery("ghost", MessageDeliveryStatus::Sent, None, 0),
            Err(LogError::Missing(id)) if id == "ghost"
        ));
        assert!(matches!(log.json_for("ghost"), Err(LogError::Missing(_))));
    }

    #[test]
    fn json_round_trips_the_stored_message() {
        let mut log = MessageLog::default();
        log.push(TestMessage::new("alice", "hello").at(1).with_id("m1"));

        let json = log.json_for("m1").expect("json");
        let back: TestMessage = serde_json::from_str(&json).expect("parse");
        assert_eq!(back, log[0]);
    }
}
