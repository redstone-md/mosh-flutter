//! The data channel: messages, delivery acks, and their dedup.

use super::*;

impl PrivateDmSession {
    pub(super) fn handle_data(&mut self, payload: Vec<u8>) -> Result<(), PrivateDmRuntimeError> {
        let envelope: DataEnvelope = decode_json(&payload)?;

        if envelope.session_id != self.session_id || envelope.participant_id == self.participant_id
        {
            return Ok(());
        }
        let expected_signer = self.verify_device_text(&envelope)?;

        // Re-ack a message we already hold BEFORE decrypting: MLS forward
        // secrecy makes a second decrypt of the same ciphertext fail, and a
        // duplicate arriving at all usually means our previous ack was lost.
        // This also covers post-restart replays — rehydrated history re-acks
        // instead of erroring on the consumed MLS secret.
        if let Some(message_id) = envelope.message_id.as_deref() {
            if self.has_inbound_message(message_id)
                || (self.devices_live()
                    && self
                        .messages
                        .iter()
                        .any(|message| message.message_id.as_deref() == Some(message_id)))
            {
                self.send_delivery_ack(message_id);
                return Ok(());
            }
        }

        let (plaintext, signer) = self
            .crypto
            .decrypt_with_signer(&decode(&envelope.ciphertext_b64)?)?;
        if expected_signer
            .as_ref()
            .is_some_and(|expected| *expected != hex::encode(&signer))
        {
            return Err(super::devices::invalid());
        }
        let (author, own) = if self.devices_live() {
            self.device_author(&signer)?
        } else {
            (envelope.from_device.clone(), false)
        };
        if !own {
            self.note_authenticated_frame(&author);
        }
        // A delivered message contradicts "typing": the hint dies at once,
        // whatever its deadline said.
        if !own {
            self.clear_peer_typing();
        }
        let ack_id = envelope.message_id.clone();
        let message = self.messages.stamp(ChatMessage {
            from_device: author,
            body: String::from_utf8_lossy(&plaintext).into_owned(),
            message_id: envelope.message_id,
            sent_at_ms: envelope.sent_at_ms,
            attachment: None,
            call_event: None,
            delivery_status: own.then(|| {
                if ack_id.as_ref().is_some_and(|id| {
                    self.membership
                        .as_ref()
                        .is_some_and(|membership| membership.peer_delivered(id))
                }) {
                    MessageDeliveryStatus::Delivered
                } else {
                    MessageDeliveryStatus::Sent
                }
            }),
            delivery_error: None,
            retryable: None,
            retry_count: None,
            read: None,
        });
        if self.messages.holds_copy_of(&message) {
            return Ok(());
        }
        self.messages.push(message);
        if let Some(message_id) = ack_id.as_deref() {
            self.send_delivery_ack(message_id);
        }

        Ok(())
    }

    /// True when an inbound (peer-authored) message with this id is already
    /// in the log — the trigger for re-acking instead of re-processing.
    pub(super) fn has_inbound_message(&self, message_id: &str) -> bool {
        self.messages.iter().any(|existing| {
            existing.from_device != self.device_id
                && existing.message_id.as_deref() == Some(message_id)
        })
    }

    /// Best-effort delivery receipt. Loss is fine: the sender keeps
    /// re-sending until a later duplicate provokes a fresh ack. The message
    /// id is MLS-encrypted so only the real peer can mint an ack — plaintext
    /// would let any mesh member fake ✓✓ and silence the resend loop.
    pub(super) fn send_delivery_ack(&mut self, message_id: &str) {
        let Ok(ciphertext) = self.crypto.encrypt(message_id.as_bytes()) else {
            return;
        };
        let envelope = ControlEnvelope::DeliveryAck {
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            ack_ciphertext_b64: encode(&ciphertext),
        };
        let Ok(payload) = serde_json::to_vec(&envelope) else {
            return;
        };
        let _ = self.route_send(ChannelKind::Control, &payload);
    }
}
