//! Queued text publication and bounded acknowledgement retries.

use super::*;

impl PrivateDmSession {
    /// Encrypt one queued message at the current epoch, publish it, and settle
    /// it `Sent`. The bytes are recorded on the attempt so the auto re-sends
    /// replay the same ciphertext the counterpart dedups on.
    pub(super) fn publish_queued(&mut self, message_id: &str) -> Result<(), PrivateDmRuntimeError> {
        let body = self
            .messages
            .iter()
            .find(|message| message.message_id.as_deref() == Some(message_id))
            .map(|message| {
                if message
                    .metadata
                    .as_ref()
                    .is_some_and(|m| m.deletion.is_some())
                {
                    self.outbound_attempts
                        .get(message_id)
                        .and_then(|a| serde_json::from_str::<ChatMessage>(&a.message_json).ok())
                        .map(|m| m.body)
                        .unwrap_or_else(|| message.body.clone())
                } else {
                    message.body.clone()
                }
            })
            .ok_or_else(|| PrivateDmRuntimeError::MissingMessage(message_id.to_string()))?;
        let sent_at_ms = self
            .outbound_attempts
            .get(message_id)
            .map(|attempt| attempt.sent_at_ms)
            .ok_or_else(|| PrivateDmRuntimeError::MissingMessage(message_id.to_string()))?;
        let ciphertext = self.crypto.encrypt(body.as_bytes())?;
        let mut envelope = DataEnvelope {
            origin: self
                .messages
                .iter()
                .find(|m| m.message_id.as_deref() == Some(message_id))
                .and_then(|m| m.metadata.as_ref())
                .and_then(|m| m.origin.clone()),
            device_signature: None,
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            from_device: self.device_id.clone(),
            message_id: Some(message_id.to_string()),
            sent_at_ms: Some(sent_at_ms),
            ciphertext_b64: encode(&ciphertext),
            resend: None,
        };
        self.sign_device_text(&mut envelope)?;
        self.track_device_receipts(message_id);
        let payload = serde_json::to_vec(&envelope)
            .map_err(|error| PrivateDmRuntimeError::Codec(error.to_string()))?;
        self.route_send(ChannelKind::Data, &payload)?;
        if let Some(attempt) = self.outbound_attempts.get_mut(message_id) {
            attempt.publish_payload_b64 = encode(&payload);
            attempt.ciphertext_bytes = ciphertext.len();
        }
        self.outbox().settle(message_id, Ok(()), OnSent::Retain)?;
        Ok(())
    }

    /// Re-send user messages the peer has not acknowledged. Moss pubsub has
    /// no store-and-forward, so a frame published into a dead/half-open link
    /// vanishes; unacked Sent attempts re-publish every AUTO_RESEND_MS until
    /// the peer's DeliveryAck lands or AUTO_RESEND_MAX gives up (old client
    /// that never acks — the message keeps its Sent status). Returns the ids
    /// whose attempt state changed so the runtime can persist them.
    pub(super) fn pump_unacked_resends(&mut self, now_ms: u64) -> Vec<String> {
        if !self.peer_joined || !self.device_outbox_ready() {
            return Vec::new();
        }
        let due: Vec<(String, String, u32)> = self
            .outbound_attempts
            .iter()
            .filter(|(_, attempt)| {
                attempt.delivery_status == MessageDeliveryStatus::Sent
                    && attempt.auto_resends < AUTO_RESEND_MAX
                    && now_ms.saturating_sub(attempt.last_send_ms) >= AUTO_RESEND_MS
            })
            .map(|(id, attempt)| {
                (
                    id.clone(),
                    attempt.publish_payload_b64.clone(),
                    attempt.auto_resends,
                )
            })
            .collect();
        let mut changed = self.finish_device_resends();
        for (message_id, payload_b64, auto_resends) in due {
            let Ok(payload) = decode(&payload_b64) else {
                continue;
            };
            // Bump the resend counter INSIDE the envelope so the re-sent
            // frame's bytes differ from the original — the receiver's
            // frame-level sha256 dedup would otherwise swallow the duplicate
            // before the re-ack path could run.
            let Ok(mut envelope) = serde_json::from_slice::<DataEnvelope>(&payload) else {
                continue;
            };
            if self.devices_live()
                && decode(&envelope.ciphertext_b64)
                    .ok()
                    .and_then(|ciphertext| MlsSessionCrypto::commit_epoch(&ciphertext).ok())
                    != self.crypto.epoch()
            {
                if self.publish_queued(&message_id).is_ok() {
                    changed.push(message_id);
                }
                continue;
            }
            envelope.resend = Some(auto_resends + 1);
            let Ok(bytes) = serde_json::to_vec(&envelope) else {
                continue;
            };
            // Only a re-send the transport took burns a slot — a refusal must
            // not exhaust the budget with zero frames on the wire.
            if self.route_send(ChannelKind::Data, &bytes).is_err() {
                continue;
            }
            if let Some(attempt) = self.outbound_attempts.get_mut(&message_id) {
                attempt.auto_resends += 1;
                attempt.last_send_ms = now_ms;
                // Session transition the field log carries: how many times a
                // message had to be re-sent before the ack arrived.
                dlog::write(
                    LogLevel::Info,
                    kinds::RESEND,
                    &self.session_id,
                    &format!("resend #{} of message {message_id}", attempt.auto_resends),
                );
                // At the cap the attempt STAYS: the filter above stops the
                // automatic loop, the message honestly keeps Sent (not
                // Delivered), and a manual retry still has its payload.
            }
            changed.push(message_id);
        }
        changed
    }
}
