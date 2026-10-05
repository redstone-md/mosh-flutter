//! Durable channel text admission, publication and deliberate retry.

use super::*;

impl ChannelRuntime {
    pub fn send(
        &mut self,
        name: &str,
        body: String,
    ) -> Result<ChannelSendResult, ChannelRuntimeError> {
        if body.len() > MAX_BODY_LEN {
            return Err(ChannelRuntimeError::BodyTooLarge);
        }
        self.drain_inbound()?;
        let normalized = normalize_name(name)?;
        let (channel_name, topic, prepared) = {
            let session = self.channel_mut(&normalized)?;
            let mut message = session.messages.stamp(ChannelMessage {
                metadata: None,
                from_device: session.display_name.clone(),
                from_fingerprint: session.device_fingerprint.clone(),
                body,
                message_id: Some(crate::message_id::occurrence_id("message")),
                sent_at_ms: None,
                attachment: None,
                delivery_status: None,
                delivery_error: None,
                retryable: None,
                retry_count: None,
            });
            session.sign_text_origin(&mut message)?;
            // A channel is public, so the frame is the message itself, minus
            // the delivery fields that only mean something to the sender.
            let payload = serde_json::to_vec(&session.publishable_message(&message))
                .map_err(|error| ChannelRuntimeError::Codec(error.to_string()))?;
            let bytes = payload.len();
            let channel_name = session.name.clone();
            let topic = session.topic.clone();
            let prepared = session
                .outbox()
                .open(message, channel_name.clone(), payload, bytes)?;
            (channel_name, topic, prepared)
        };
        let result = self.publish_prepared(&normalized, &topic, channel_name, prepared)?;
        self.channels.persist_tail_logged(KIND);
        Ok(result)
    }

    pub fn retry_message(
        &mut self,
        name: &str,
        message_id: &str,
    ) -> Result<ChannelSendResult, ChannelRuntimeError> {
        self.drain_inbound()?;
        let normalized = normalize_name(name)?;
        let (channel_name, topic, prepared) = {
            let session = self.channel_mut(&normalized)?;
            let prepared = session.outbox().reopen(message_id)?;
            (session.name.clone(), session.topic.clone(), prepared)
        };
        let result = self.publish_prepared(&normalized, &topic, channel_name, prepared)?;
        self.channels.persist_tail_logged(KIND);
        Ok(result)
    }

    pub(super) fn persist_prepared(
        &mut self,
        normalized: &str,
        message_id: &str,
    ) -> Result<(), ChannelRuntimeError> {
        if let Err(error) = self.channels.persist_send(normalized, message_id, false) {
            self.channel_mut(normalized)?.outbox().settle(
                message_id,
                Err(error.to_string()),
                OnSent::Retain,
            )?;
            if let Err(save_error) = self.channels.persist_send(normalized, message_id, false) {
                dlog::write(
                    LogLevel::Error,
                    kinds::PERSIST,
                    normalized,
                    &save_error.to_string(),
                );
            }
            return Err(error.into());
        }
        Ok(())
    }

    /// Publishes a prepared send on the channel's topic and writes down how it
    /// went. A channel has no acknowledgement, so the attempt record is gone
    /// as soon as the frame is on the wire.
    pub(super) fn publish_prepared(
        &mut self,
        normalized: &str,
        topic: &str,
        channel_name: String,
        prepared: Prepared,
    ) -> Result<ChannelSendResult, ChannelRuntimeError> {
        self.persist_prepared(normalized, &prepared.message_id)?;
        let publish = {
            let session = self.channel_ref(normalized)?;
            session
                .node
                .publish_room(&session.mesh_id, topic, &prepared.payload)
                .map_err(|error| ChannelRuntimeError::Moss(error.to_string()))
        };
        let settled = {
            let session = self.channel_mut(normalized)?;
            session.outbox().settle(
                &prepared.message_id,
                publish.map_err(|error| error.to_string()),
                OnSent::Forget,
            )?
        };
        if let Err(error) = self
            .channels
            .persist_send(normalized, &prepared.message_id, false)
        {
            dlog::write(
                LogLevel::Error,
                kinds::PERSIST,
                normalized,
                &error.to_string(),
            );
        }
        Ok(ChannelSendResult {
            name: channel_name,
            bytes: prepared.ciphertext_bytes,
            message_id: prepared.message_id,
            sent_at_ms: prepared.sent_at_ms,
            delivery_status: settled.status,
            delivery_error: settled.error,
        })
    }
}

impl ChannelSession {
    fn sign_text_origin(&self, message: &mut ChannelMessage) -> Result<(), ChannelRuntimeError> {
        let origin = crate::message_deletion::MessageOrigin::sign(
            &format!("channel:{}", self.name),
            message.message_id.as_deref().unwrap_or_default(),
            message.body.as_bytes(),
            self.node
                .identity_signer()
                .map_err(|e| ChannelRuntimeError::Moss(e.to_string()))?,
            self.deletions.store.as_ref(),
        )
        .map_err(ChannelRuntimeError::Codec)?;
        message.metadata = Some(crate::message_deletion::MessageMetadata {
            origin: Some(origin),
            ..Default::default()
        });
        Ok(())
    }
}
