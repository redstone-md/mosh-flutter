//! The typing signal: publish cadence and the peer-hint window.

use super::*;

impl PrivateDmSession {
    /// Publishes a typing hint if the refresh cadence allows one. The
    /// composer calls this on every keystroke; continued input keeps
    /// refreshing the peer's window at this cadence, and stopping input
    /// simply stops the calls — the peer's own expiry does the rest. No
    /// sender-side expiry state: the receiver owns the deadline.
    pub(super) fn publish_typing(&mut self, now: u64) {
        if !self.can_encrypt_for_peer() {
            return;
        }
        if !self.typing_gate.send_due(now) {
            return;
        }
        let body = TypingBody {
            device: self.device_id.clone(),
            until_ms: TypingGate::deadline(now),
        };
        let Ok(body_json) = serde_json::to_vec(&body) else {
            return;
        };
        let Ok(ciphertext) = self.crypto.encrypt(&body_json) else {
            return;
        };
        let envelope = ControlEnvelope::TypingIndicator {
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            from_device: self.device_id.clone(),
            typing_ciphertext_b64: encode(&ciphertext),
        };
        let Ok(payload) = serde_json::to_vec(&envelope) else {
            return;
        };
        let _ = self.route_send(ChannelKind::Control, &payload);
    }

    /// A decrypted hint from the counterpart: stamp the deadline from OUR
    /// clock (the sender's `until_ms` stays advisory) and file the event.
    pub(super) fn note_peer_typing(&mut self, now: u64) {
        let lapsed = self.peer_typing_until_ms.is_none_or(|until| until <= now);
        self.peer_typing_until_ms = Some(TypingGate::deadline(now));
        if lapsed {
            typing_shared::push_typing_event(&self.session_id, "started");
        }
    }

    /// Drops the hint once its deadline passes. Driven by the poll/tick
    /// heartbeat, so no timer of its own; files the lapse event once.
    pub(super) fn expire_peer_typing(&mut self, now: u64) {
        let Some(until) = self.peer_typing_until_ms else {
            return;
        };
        if until > now {
            return;
        }
        self.peer_typing_until_ms = None;
        typing_shared::push_typing_event(&self.session_id, "stopped");
    }

    /// An inbound message contradicts "typing": the hint is cleared at once,
    /// whatever its deadline said.
    pub(super) fn clear_peer_typing(&mut self) {
        if self.peer_typing_until_ms.take().is_some() {
            typing_shared::push_typing_event(&self.session_id, "stopped");
        }
    }

    /// The read flag ONE snapshot row carries: `Some(true)` only for the
    /// user's own message the counterpart's authenticated receipt named —
    /// keyed off the persisted id set so a rehydrated row (whose on-disk
    /// `read` may predate the field) reads the same after a restart.
    /// Counterpart messages carry `None`: they have nothing to learn about
    /// their own reads.
    pub(super) fn own_message_read(&self, message: &ChatMessage) -> Option<bool> {
        if message.from_device != self.device_id {
            return None;
        }
        let message_id = message.message_id.as_deref()?;
        self.peer_read_ids
            .iter()
            .any(|id| id == message_id)
            .then_some(true)
    }

    /// One read receipt: the counterpart has seen this message of ours.
    /// Marks the log row (`read: Some(true)`) so the snapshot carries it,
    /// files the pinned `message_read` event, and notes the id so a restart
    /// does not re-ask. Unknown ids (a receipt for a message a restart
    /// already dropped) are ignored, exactly like the DeliveryAck.
    pub(super) fn note_peer_read(&mut self, message_id: &str) {
        if self.peer_read_ids.iter().any(|id| id == message_id) {
            return;
        }
        let Some(message) = self.messages.find_mut(message_id) else {
            return;
        };
        if message.from_device != self.device_id {
            return;
        }
        self.peer_read_ids.push(message_id.to_string());
        if self.peer_read_ids.len() > READ_HISTORY_KEEP {
            self.peer_read_ids = prune_read_ids(&self.peer_read_ids);
        }
        message.read = Some(true);
        self.record_dirty = true;
        push_read_event(&self.session_id, message_id, "peer-read");
    }

    /// The user is looking at this DM: receipt every counterpart message
    /// not yet read, one MLS-encrypted frame per message (the ack shape — a
    /// lost receipt re-sends as the same single-frame problem). Already
    /// receipted ids are skipped so nothing re-sends. Runs only under an
    /// enabled toggle; the runtime checks that before calling.
    pub(super) fn mark_viewed(&mut self) {
        if !self.can_encrypt_for_peer() {
            return;
        }
        let unread: Vec<String> = self
            .messages
            .iter()
            .filter(|message| self.message_needs_receipt(message))
            .filter_map(|message| message.message_id.clone())
            .filter(|message_id| !self.sent_read_ids.contains(message_id))
            .collect();
        for message_id in unread {
            self.send_read_receipt(&message_id);
            // The receiver's own honest event log: one `message_read` per
            // receipt this side sent, matching the frame on the wire.
            push_read_event(&self.session_id, &message_id, "self-read");
            self.sent_read_ids.push(message_id);
        }
        // The ids we receipted are re-derivable from the rehydrated history
        // (see `to_persisted_record`), so they stay memory-only; nothing to
        // persist here beyond what the message rows carry.
    }

    /// True for a counterpart message that is not a call-event stub and
    /// carries an id — the only messages a receipt means anything for.
    pub(super) fn message_needs_receipt(&self, message: &ChatMessage) -> bool {
        message.from_device != self.device_id
            && message.call_event.is_none()
            && message.message_id.is_some()
    }

    /// One MLS-encrypted receipt frame for one message id. Best-effort, like
    /// the DeliveryAck: a lost receipt is answered by the peer's next
    /// `mark_viewed` (its `sent_read_ids` only stops re-sends while this
    /// process lives, so a restart re-asks for anything not settled).
    pub(super) fn send_read_receipt(&mut self, message_id: &str) {
        let body = ReadReceiptBody {
            message_id: message_id.to_string(),
        };
        let Ok(body_json) = serde_json::to_vec(&body) else {
            return;
        };
        let Ok(ciphertext) = self.crypto.encrypt(&body_json) else {
            return;
        };
        let envelope = ControlEnvelope::ReadReceipt {
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            receipt_ciphertext_b64: encode(&ciphertext),
        };
        let Ok(payload) = serde_json::to_vec(&envelope) else {
            return;
        };
        let _ = self.route_send(ChannelKind::Control, &payload);
    }
}
