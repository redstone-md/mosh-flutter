//! The one path a message takes on its way out.
//!
//! The three kinds publish differently — a channel sends in the clear, a group
//! encrypts and publishes on its data channel, a DM routes through the relay —
//! but everything around that one step is the same. Stamp the message, file an
//! attempt record so a restart can still find the bytes, publish, write down
//! what happened on both the message and the record, and drop the record once
//! the kind is done with it. That work lives here once.
//!
//! A send runs in three calls because the transport sits in the middle:
//!
//! 1. [`Outbox::open`] for a first send, or [`Outbox::reopen`] for a re-send.
//! 2. The kind publishes the [`Prepared::payload`] its own way.
//! 3. [`Outbox::settle`] records the result.
//!
//! The runtime persists between the calls, so it borrows a fresh `Outbox` for
//! each one rather than holding it across the publish.

use std::collections::HashMap;

use super::message_log::{ConversationMessage, LogError, MessageLog};
use super::{decode, encode, now_ms};
use crate::outbound_delivery::{MessageDeliveryStatus, OutboundAttemptRecord};

/// A send ready for the transport.
pub struct Prepared {
    pub message_id: String,
    pub sent_at_ms: u64,
    pub ciphertext_bytes: usize,
    pub retry_count: u32,
    pub payload: Vec<u8>,
}

/// How a send ended, in the form the runtime hands back to the app.
pub struct Settled {
    pub status: MessageDeliveryStatus,
    pub error: Option<String>,
}

/// What becomes of the attempt record once the transport takes the frame.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OnSent {
    /// Drop it. A channel and a group are done: the frame is on the wire and
    /// nothing will report back.
    Forget,
    /// Keep it. In a DM `Sent` only means the frame left, and the record holds
    /// the bytes the auto re-sends replay until the peer's DeliveryAck lands.
    Retain,
}

/// The message log and the attempts still in flight, borrowed together for one
/// step of a send. Runtimes keep the two as separate fields and build an
/// outbox where they need both.
pub struct Outbox<'a, M> {
    log: &'a mut MessageLog<M>,
    attempts: &'a mut HashMap<String, OutboundAttemptRecord>,
}

impl<'a, M: ConversationMessage> Outbox<'a, M> {
    pub fn new(
        log: &'a mut MessageLog<M>,
        attempts: &'a mut HashMap<String, OutboundAttemptRecord>,
    ) -> Self {
        Self { log, attempts }
    }

    /// Files a first send: the message goes into the log as Pending and its
    /// payload into an attempt record that survives a restart. The message
    /// must already be stamped, because the kind needs its id and time to
    /// build the payload.
    ///
    /// `ciphertext_bytes` is what the kind counts as the size of the send: the
    /// ciphertext where there is one, the frame itself in a public channel.
    pub fn open(
        &mut self,
        message: M,
        conversation_id: String,
        payload: Vec<u8>,
        ciphertext_bytes: usize,
    ) -> Result<Prepared, LogError> {
        let message_id = message.message_id().unwrap_or_default().to_string();
        let sent_at_ms = message.sent_at_ms().unwrap_or_else(now_ms);
        self.log.upsert(message);
        self.log
            .mark_delivery(&message_id, MessageDeliveryStatus::Pending, None, 0)?;
        self.attempts.insert(
            message_id.clone(),
            OutboundAttemptRecord {
                conversation_id,
                message_id: message_id.clone(),
                sent_at_ms,
                ciphertext_bytes,
                message_json: self.log.json_for(&message_id)?,
                publish_payload_b64: encode(&payload),
                delivery_status: MessageDeliveryStatus::Pending,
                delivery_error: None,
                retry_count: 0,
                // Only a DM acks, so only a DM ever moves these two.
                auto_resends: 0,
                last_send_ms: sent_at_ms,
            },
        );
        Ok(Prepared {
            message_id,
            sent_at_ms,
            ciphertext_bytes,
            retry_count: 0,
            payload,
        })
    }

    /// Prepares a re-send of a message that still has an attempt record: the
    /// retry count goes up, message and record go back to Pending, and the
    /// stored payload comes back out unchanged, so the peer sees the same
    /// bytes it would have seen the first time.
    pub fn reopen(&mut self, message_id: &str) -> Result<Prepared, LogError> {
        let attempt = self
            .attempts
            .get_mut(message_id)
            .ok_or_else(|| LogError::Missing(message_id.to_string()))?;
        attempt.retry_count = attempt.retry_count.saturating_add(1);
        attempt.delivery_status = MessageDeliveryStatus::Pending;
        attempt.delivery_error = None;
        let prepared = Prepared {
            message_id: message_id.to_string(),
            sent_at_ms: attempt.sent_at_ms,
            ciphertext_bytes: attempt.ciphertext_bytes,
            retry_count: attempt.retry_count,
            payload: decode(&attempt.publish_payload_b64)?,
        };
        self.log.mark_delivery(
            message_id,
            MessageDeliveryStatus::Pending,
            None,
            prepared.retry_count,
        )?;
        self.sync_message_json(message_id)?;
        Ok(prepared)
    }

    /// Records what the transport said. The retry count comes off the attempt
    /// record, so a first send and a re-send settle by the same rule.
    pub fn settle(
        &mut self,
        message_id: &str,
        outcome: Result<(), String>,
        on_sent: OnSent,
    ) -> Result<Settled, LogError> {
        let retry_count = self
            .attempts
            .get(message_id)
            .map_or(0, |attempt| attempt.retry_count);
        match outcome {
            Ok(()) => {
                self.log.mark_delivery(
                    message_id,
                    MessageDeliveryStatus::Sent,
                    None,
                    retry_count,
                )?;
                match on_sent {
                    OnSent::Forget => {
                        self.attempts.remove(message_id);
                    }
                    OnSent::Retain => {
                        if let Some(attempt) = self.attempts.get_mut(message_id) {
                            attempt.delivery_status = MessageDeliveryStatus::Sent;
                            attempt.delivery_error = None;
                            attempt.last_send_ms = now_ms();
                        }
                        self.sync_message_json(message_id)?;
                    }
                }
                Ok(Settled {
                    status: MessageDeliveryStatus::Sent,
                    error: None,
                })
            }
            Err(error) => {
                if let Some(attempt) = self.attempts.get_mut(message_id) {
                    attempt.delivery_status = MessageDeliveryStatus::Failed;
                    attempt.delivery_error = Some(error.clone());
                }
                self.log.mark_delivery(
                    message_id,
                    MessageDeliveryStatus::Failed,
                    Some(error.clone()),
                    retry_count,
                )?;
                self.sync_message_json(message_id)?;
                Ok(Settled {
                    status: MessageDeliveryStatus::Failed,
                    error: Some(error),
                })
            }
        }
    }

    /// Copies the message's current JSON into its attempt record, so a restart
    /// rebuilds the message with the delivery status it ended on.
    pub fn sync_message_json(&mut self, message_id: &str) -> Result<(), LogError> {
        let message_json = self.log.json_for(message_id)?;
        if let Some(attempt) = self.attempts.get_mut(message_id) {
            attempt.message_json = message_json;
        }
        Ok(())
    }
}

#[cfg(test)]
#[path = "outbound_tests.rs"]
mod tests;
