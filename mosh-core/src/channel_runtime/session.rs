//! Outbound shape and inbound message handling.

use super::*;

impl ChannelSession {
    pub(super) fn publishable_message(&self, message: &ChannelMessage) -> ChannelMessage {
        let mut publishable = message.clone();
        publishable.delivery_status = None;
        publishable.delivery_error = None;
        publishable.retryable = None;
        publishable.retry_count = None;
        publishable
    }

    /// The message log and the attempts in flight, borrowed together for one
    /// step of a send.
    pub(super) fn outbox(&mut self) -> Outbox<'_, ChannelMessage> {
        Outbox::new(&mut self.messages, &mut self.outbound_attempts)
    }

    pub(super) fn handle_message(
        &mut self,
        message: MossReceivedMessage,
    ) -> Result<(), ChannelRuntimeError> {
        if message.channel != self.blob_topic
            && self.seen.seen_before(&message.channel, &message.payload)
        {
            return Ok(());
        }
        if message.channel == self.topic {
            let envelope = self.decode_channel_message(&message.payload)?;
            if self
                .messages
                .iter()
                .any(|existing| existing.message_id == envelope.message_id)
            {
                // Native action targets cannot refer to two different authors.
                if self.messages.holds_copy_of(&envelope) {
                    return Ok(());
                }
                return Err(ChannelRuntimeError::Codec(
                    "conflicting channel occurrence".into(),
                ));
            }
            if envelope.from_fingerprint == self.device_fingerprint {
                return Ok(());
            }
            self.messages.push_stamped(envelope);
            Ok(())
        } else if message.channel == self.blob_topic {
            self.handle_blob(message.payload)
        } else {
            Ok(())
        }
    }

    fn decode_channel_message(
        &self,
        payload: &[u8],
    ) -> Result<ChannelMessage, ChannelRuntimeError> {
        let mut envelope: ChannelMessage = serde_json::from_slice(payload)
            .map_err(|error| ChannelRuntimeError::Codec(error.to_string()))?;
        let origin = envelope.metadata.as_ref().and_then(|m| m.origin.clone());
        envelope.metadata = None;
        if let Some(origin) = origin {
            origin
                .verify(
                    &format!("channel:{}", self.name),
                    envelope.message_id.as_deref().unwrap_or_default(),
                    envelope.body.as_bytes(),
                )
                .map_err(ChannelRuntimeError::Codec)?;
            if origin.author != envelope.from_fingerprint.to_lowercase() {
                return Err(ChannelRuntimeError::Codec(
                    "channel origin author mismatch".into(),
                ));
            }
            envelope.metadata = Some(crate::message_deletion::MessageMetadata {
                origin: Some(origin),
                ..Default::default()
            });
        }
        self.set_verified_ownership(&mut envelope)?;
        self.prepare_legacy_message(&mut envelope)?;
        Ok(envelope)
    }

    /// Assigned only after this owner verified the original full-key content proof.
    pub(super) fn set_verified_ownership(
        &self,
        message: &mut ChannelMessage,
    ) -> Result<(), ChannelRuntimeError> {
        let Some(origin) = message.metadata.as_ref().and_then(|m| m.origin.as_ref()) else {
            return Ok(());
        };
        let own = self.deletion_authority()?.is_author(origin);
        message.metadata.as_mut().unwrap().is_own = Some(own);
        Ok(())
    }

    // Blob traffic stays on the room wire (spec #8, this slice): a channel
    // has no single direct peer to stream to, and the stream carrier is the
    // DM fast path only. The chunk protocol below is unchanged.
}
