//! DM admission and the durable dequeue used by commands and background ticks.
use super::*;

impl PrivateDmRuntime {
    /// Admits a text to durable history, then queues it for the shared dequeue.
    /// A refused admission stays Failed. Accepted queued attempts retry when
    /// storage and transport allow publication.
    pub fn send_message(
        &mut self,
        session_id: &str,
        body: String,
    ) -> Result<SendMessageResult, PrivateDmRuntimeError> {
        self.drain_inbound();
        let message_id = self.session_mut(session_id)?.file_text(body)?;
        self.admit_queued(session_id, &message_id)?;
        if let Err(error) = self.deliver_queued(session_id) {
            dlog::write(
                LogLevel::Error,
                kinds::PERSIST,
                session_id,
                &error.to_string(),
            );
        }
        let result = self.send_result(session_id, &message_id)?;
        if let Err(error) = self.sessions.persist_tail() {
            self.log_persistence_failure(session_id, &error);
        }
        Ok(result)
    }

    /// Puts a failed message back in the queue. A message that is already
    /// waiting its turn is left alone and reported as it stands.
    pub fn retry_message(
        &mut self,
        session_id: &str,
        message_id: &str,
    ) -> Result<SendMessageResult, PrivateDmRuntimeError> {
        self.drain_inbound();
        {
            let session = self.session_mut(session_id)?;
            let attempt = session
                .outbound_attempts
                .get(message_id)
                .ok_or_else(|| PrivateDmRuntimeError::MissingMessage(message_id.to_string()))?;
            if matches!(
                attempt.delivery_status,
                MessageDeliveryStatus::Queued | MessageDeliveryStatus::Pending
            ) {
                return self.send_result(session_id, message_id);
            }
            session.outbox().reopen(message_id)?;
        }
        self.admit_queued(session_id, message_id)?;
        if let Err(error) = self.deliver_queued(session_id) {
            dlog::write(
                LogLevel::Error,
                kinds::PERSIST,
                session_id,
                &error.to_string(),
            );
        }
        self.send_result(session_id, message_id)
    }

    /// Pending is provisional admission, so even an uncertain refused commit
    /// cannot restore an automatically publishable attempt on the next launch.
    fn admit_queued(
        &mut self,
        session_id: &str,
        message_id: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        if let Err(error) = self.sessions.persist_admission(session_id, message_id) {
            self.session_mut(session_id)?.outbox().settle(
                message_id,
                Err(error.to_string()),
                OnSent::Retain,
            )?;
            if let Err(save_error) = self.sessions.persist_send(session_id, message_id, true) {
                self.log_persistence_failure(session_id, &save_error);
            }
            return Err(error.into());
        }
        self.session_mut(session_id)?
            .outbox()
            .activate_queue(message_id)?;
        if let Err(error) = self.sessions.persist_send(session_id, message_id, true) {
            self.log_persistence_failure(session_id, &error);
        }
        Ok(())
    }

    /// Give one session's outbox a turn right now, and write down whatever it
    /// settled.
    pub(super) fn deliver_queued(&mut self, session_id: &str) -> Result<(), PrivateDmRuntimeError> {
        let Some(session) = self.sessions.get(session_id) else {
            return Ok(());
        };
        if !session.can_encrypt_for_peer() || !session.device_outbox_ready() {
            return Ok(());
        }
        let queued = queued_in_order(&session.outbound_attempts);
        for message_id in queued {
            self.sessions.persist_send(session_id, &message_id, true)?;
            if let Err(error) = self.session_mut(session_id)?.publish_queued(&message_id) {
                dlog::write(
                    LogLevel::Warn,
                    kinds::OUTBOX,
                    session_id,
                    &format!("queued message {message_id} stays queued: {error}"),
                );
                break;
            }
            if let Err(error) = self.sessions.persist_send(session_id, &message_id, true) {
                self.log_persistence_failure(session_id, &error);
                break;
            }
        }
        Ok(())
    }

    /// How one message's send stands, as the app is told.
    fn send_result(
        &self,
        session_id: &str,
        message_id: &str,
    ) -> Result<SendMessageResult, PrivateDmRuntimeError> {
        let session = self.session_ref(session_id)?;
        let attempt = session
            .outbound_attempts
            .get(message_id)
            .ok_or_else(|| PrivateDmRuntimeError::MissingMessage(message_id.to_string()))?;
        Ok(SendMessageResult {
            session_id: session.session_id.clone(),
            state: session.state,
            ciphertext_bytes: attempt.ciphertext_bytes,
            message_id: message_id.to_string(),
            sent_at_ms: attempt.sent_at_ms,
            delivery_status: attempt.delivery_status,
            delivery_error: attempt.delivery_error.clone(),
        })
    }
}

impl PrivateDmSession {
    fn file_text(&mut self, body: String) -> Result<String, PrivateDmRuntimeError> {
        self.ensure_device_authorized()?;
        let mut message = self.messages.stamp(ChatMessage {
            metadata: None,
            from_device: self.device_id.clone(),
            body,
            message_id: Some(crate::message_id::occurrence_id("message")),
            sent_at_ms: None,
            attachment: None,
            call_event: None,
            delivery_status: None,
            delivery_error: None,
            retryable: None,
            retry_count: None,
            read: None,
        });
        message.metadata = Some(crate::message_deletion::MessageMetadata {
            origin: Some(
                crate::message_deletion::MessageOrigin::sign_mls(
                    &format!("dm:{}", self.session_id),
                    message.message_id.as_deref().unwrap_or_default(),
                    message.body.as_bytes(),
                    &self.crypto,
                    self.deletions.store.as_ref(),
                    self.transport.local_peer_id().as_deref(),
                )
                .map_err(PrivateDmRuntimeError::Codec)?,
            ),
            is_own: Some(true),
            ..Default::default()
        });
        let session_id = self.session_id.clone();
        Ok(self
            .outbox()
            .open(message, session_id, Vec::new(), 0)?
            .message_id)
    }
}
