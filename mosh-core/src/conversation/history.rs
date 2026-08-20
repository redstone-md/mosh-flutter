//! The history a conversation keeps on disk.
//!
//! The three kinds do the same four things with it: list the conversations
//! saved last time, read one of them back, append the messages gained since
//! the last write, and write down where a single send got to. Only the tables
//! differ, and those arrive as data ([`HistoryTables`]), so the routine is
//! written once here rather than three times in the runtimes.
//!
//! Writes stay cheap because the store remembers how many messages of each
//! conversation are already down and starts the next append from there. Lose
//! that count and every poll rewrites the whole history.
//!
//! What stays with the kind: its own session record, its MLS snapshot, and
//! when a record is worth rewriting.

use std::collections::HashMap;

use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};

use super::attachments::AttachmentDirection;
use super::message_log::{delivery_meta, ConversationMessage, MessageLog};
use super::now_ms;
use super::transfer::Transfer;
use crate::outbound_delivery::{MessageDeliveryStatus, OutboundAttemptRecord};
use crate::persistence::{HistoryTables, Persistence};

/// What a message that was still in flight when the app closed reports.
const INTERRUPTED_SEND: &str = "app closed before the send completed";

/// One message as it sits in the store. The id and the time are repeated
/// outside the message because they are also the key it is filed under.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoredMessage<M> {
    pub conversation_id: String,
    pub sent_at_ms: u64,
    pub message_id: String,
    pub message: M,
}

/// Where a replayed conversation's rows land.
pub struct Restore<'a, M> {
    pub log: &'a mut MessageLog<M>,
    pub attempts: &'a mut HashMap<String, OutboundAttemptRecord>,
    pub transfer: &'a mut Transfer,
    /// This device's author string. A message from it is one this device sent.
    pub local_author: &'a str,
}

/// The stored history of one kind of conversation, and how much of it is
/// already written.
pub struct History {
    tables: HistoryTables,
    persisted_counts: HashMap<String, usize>,
}

impl History {
    pub fn new(tables: HistoryTables) -> Self {
        Self {
            tables,
            persisted_counts: HashMap::new(),
        }
    }

    /// The record of every conversation saved last time. A record that will
    /// not parse is skipped with a warning: one bad row must not keep the rest
    /// of the history from coming back.
    pub fn stored_conversations<R: DeserializeOwned>(&self, p: &Persistence) -> Vec<R> {
        let Ok(rows) = p.list_conversations(self.tables) else {
            return Vec::new();
        };
        rows.iter()
            .filter_map(|row| match serde_json::from_slice(row) {
                Ok(record) => Some(record),
                Err(error) => {
                    eprintln!("rehydrate: bad {} row: {error}", self.tables.label);
                    None
                }
            })
            .collect()
    }

    /// Reads one conversation's messages and unsettled sends back in, restores
    /// the attachments still cached on disk, and remembers how much of the
    /// history is already written.
    pub fn replay<M>(&mut self, p: &Persistence, conversation_id: &str, into: Restore<'_, M>)
    where
        M: ConversationMessage + DeserializeOwned,
    {
        let Restore {
            log,
            attempts,
            transfer,
            local_author,
        } = into;

        if let Ok(rows) = p.list_history_messages(self.tables, conversation_id) {
            for row in rows {
                let Ok(stored) = serde_json::from_slice::<StoredMessage<M>>(&row) else {
                    continue;
                };
                let mut message = stored.message;
                fill_in(&mut message, &stored.message_id, stored.sent_at_ms);
                restore_attachment(&message, local_author, transfer);
                log.upsert(message);
            }
        }

        if let Ok(rows) = p.list_outbound_attempts(self.tables.outbound_scope, conversation_id) {
            for row in rows {
                let Ok(mut attempt) = serde_json::from_slice::<OutboundAttemptRecord>(&row) else {
                    continue;
                };
                // A Pending attempt cannot survive a restart: whoever held it
                // died with the process, so nothing will ever settle it.
                // Surface a retryable failure instead of a forever-spinner.
                if attempt.delivery_status == MessageDeliveryStatus::Pending {
                    attempt.delivery_status = MessageDeliveryStatus::Failed;
                    attempt.delivery_error = Some(INTERRUPTED_SEND.to_string());
                }
                let Ok(mut message) = serde_json::from_str::<M>(&attempt.message_json) else {
                    continue;
                };
                fill_in(&mut message, &attempt.message_id, attempt.sent_at_ms);
                message.set_delivery(delivery_meta(
                    attempt.delivery_status,
                    attempt.delivery_error.clone(),
                    attempt.retry_count,
                ));
                log.upsert(message);
                attempts.insert(attempt.message_id.clone(), attempt);
            }
        }

        self.persisted_counts
            .insert(conversation_id.to_string(), log.len());
    }

    /// Appends the messages this conversation has gained since the last write.
    /// `true` when something was written — the signal a kind uses to decide
    /// whether the rest of its state is worth saving too.
    pub fn write_tail<M: ConversationMessage>(
        &mut self,
        p: &Persistence,
        conversation_id: &str,
        log: &MessageLog<M>,
    ) -> bool {
        let start = self
            .persisted_counts
            .get(conversation_id)
            .copied()
            .unwrap_or(0);
        if log.len() <= start {
            return false;
        }
        for (index, message) in log.iter().enumerate().skip(start) {
            let sent_at_ms = message.sent_at_ms().unwrap_or_else(now_ms);
            let message_id = match message.message_id() {
                Some(id) => id.to_string(),
                None => format!("{sent_at_ms}-{index:06}"),
            };
            let mut stored = message.clone();
            fill_in(&mut stored, &message_id, sent_at_ms);
            self.append(p, conversation_id, sent_at_ms, &message_id, stored);
        }
        self.persisted_counts
            .insert(conversation_id.to_string(), log.len());
        true
    }

    /// Writes one message and the state of its send. No attempt record means
    /// the send is over and nothing needs replaying, so the stored record goes
    /// away. `false` when the message is not in the log, which leaves the rest
    /// of the conversation's state alone as well.
    pub fn write_send<M: ConversationMessage>(
        &self,
        p: &Persistence,
        conversation_id: &str,
        message_id: &str,
        log: &MessageLog<M>,
        attempts: &HashMap<String, OutboundAttemptRecord>,
    ) -> bool {
        let Some(message) = log
            .iter()
            .find(|message| message.message_id() == Some(message_id))
        else {
            return false;
        };
        let sent_at_ms = message.sent_at_ms().unwrap_or_else(now_ms);
        self.append(p, conversation_id, sent_at_ms, message_id, message.clone());
        let scope = self.tables.outbound_scope;
        match attempts
            .get(message_id)
            .and_then(|attempt| serde_json::to_vec(attempt).ok())
        {
            Some(row) => {
                let _ = p.put_outbound_attempt(scope, conversation_id, message_id, &row);
            }
            None => {
                let _ = p.delete_outbound_attempt(scope, conversation_id, message_id);
            }
        }
        true
    }

    /// Writes the record a conversation is rebuilt from at startup.
    pub fn write_record<R: Serialize>(&self, p: &Persistence, conversation_id: &str, record: &R) {
        if let Ok(json) = serde_json::to_vec(record) {
            let _ = p.put_conversation(self.tables, conversation_id, &json);
        }
    }

    /// Forgets how much of a conversation is written, so the next tail write
    /// starts from the beginning. For one that was deleted, or one about to be
    /// loaded again from scratch.
    pub fn forget(&mut self, conversation_id: &str) {
        self.persisted_counts.remove(conversation_id);
    }

    fn append<M: ConversationMessage>(
        &self,
        p: &Persistence,
        conversation_id: &str,
        sent_at_ms: u64,
        message_id: &str,
        message: M,
    ) {
        let record = StoredMessage {
            conversation_id: conversation_id.to_string(),
            sent_at_ms,
            message_id: message_id.to_string(),
            message,
        };
        if let Ok(json) = serde_json::to_vec(&record) {
            let _ = p.append_history_message(
                self.tables,
                conversation_id,
                sent_at_ms,
                message_id,
                &json,
            );
        }
    }
}

/// A message stored before ids and times were carried on the message itself
/// can be missing them. The row it came from has both.
fn fill_in<M: ConversationMessage>(message: &mut M, message_id: &str, sent_at_ms: u64) {
    if message.message_id().is_none() {
        message.set_message_id(message_id.to_string());
    }
    if message.sent_at_ms().is_none() {
        message.set_sent_at_ms(sent_at_ms);
    }
}

/// Hands a stored message's attachment back to the transfer, which keeps it
/// only if its bytes are still on disk. Which way round it went is decided
/// here: a message this device wrote carries a file this device sent.
fn restore_attachment<M: ConversationMessage>(
    message: &M,
    local_author: &str,
    transfer: &mut Transfer,
) {
    let Some(descriptor) = message.attachment() else {
        return;
    };
    let direction = if message.author() == local_author {
        AttachmentDirection::Outgoing
    } else {
        AttachmentDirection::Incoming
    };
    transfer.restore_cached(descriptor, direction);
}

#[cfg(test)]
#[path = "history_tests.rs"]
mod tests;
