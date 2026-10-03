//! The voice call: offer/accept/decline/end, signaling pumps, frames.

use super::*;

impl PrivateDmSession {
    /// Sends one Call* control frame through the transport. Only the media
    /// frames skip the chokepoint's refusal rules (see `call_send_frame`).
    pub(super) fn send_call_control(
        &self,
        envelope: &ControlEnvelope,
    ) -> Result<(), PrivateDmRuntimeError> {
        let payload = serde_json::to_vec(envelope)
            .map_err(|error| PrivateDmRuntimeError::Codec(error.to_string()))?;
        self.route_send(ChannelKind::Control, &payload)
    }

    /// Builds and sends a `CallOffer` for a call already in `self.call`. The
    /// body is re-encrypted on every send: MLS deletes the secret behind an
    /// application message once consumed, so a byte-identical replay would fail
    /// to decrypt on the far side instead of re-ringing.
    pub(super) fn publish_call_offer(
        &mut self,
        call_id: &str,
        key_b64: &str,
        nonce_prefix_b64: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        let body = CallOfferBody {
            key_b64: key_b64.to_string(),
            nonce_prefix_b64: nonce_prefix_b64.to_string(),
        };
        let offer_ciphertext_b64 = self.crypto.encrypt_json(&body)?;
        let envelope = ControlEnvelope::CallOffer {
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            from_device: self.device_id.clone(),
            call_id: call_id.to_string(),
            offer_ciphertext_b64,
        };
        self.send_call_control(&envelope)
    }

    pub(super) fn publish_call_accept(&self, call_id: &str) -> Result<(), PrivateDmRuntimeError> {
        let envelope = ControlEnvelope::CallAccept {
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            call_id: call_id.to_string(),
        };
        self.send_call_control(&envelope)
    }

    pub(super) fn call_start(&mut self) -> Result<CallStarted, PrivateDmRuntimeError> {
        if !self.ready_for_user_actions() {
            return Err(PrivateDmRuntimeError::NotReady);
        }
        if self.call.is_some() {
            return Err(PrivateDmRuntimeError::Attachment(
                "another call is already in flight".to_string(),
            ));
        }
        let call_id = self.crypto.random_token("call")?;
        let key_b64 = random_b64(32);
        let nonce_prefix_b64 = random_b64(4);
        self.call = Some(CallState::outgoing(
            call_id.clone(),
            key_b64.clone(),
            nonce_prefix_b64.clone(),
            String::new(),
        ));
        // A subscribe or offer that never left must not strand the slot: no
        // frame ever arrives for a call the peer never heard of, so the
        // timeout would only clear a dead call while blocking new ones.
        if let Err(error) = self
            .transport
            .subscribe(&self.mesh_id, &voice_call_channel(&call_id))
            .map_err(PrivateDmRuntimeError::Moss)
            .and_then(|()| self.publish_call_offer(&call_id, &key_b64, &nonce_prefix_b64))
        {
            let _ = self.call.take();
            return Err(error);
        }
        if let Some(call) = self.call.as_mut() {
            call.mark_offer_sent(now_ms());
        }
        Ok(CallStarted {
            session_id: self.session_id.clone(),
            call_id,
            key_b64,
            nonce_prefix_b64,
        })
    }

    pub(super) fn call_accept(&mut self, call_id: &str) -> Result<(), PrivateDmRuntimeError> {
        let Some(call) = self.call.as_mut() else {
            return Err(PrivateDmRuntimeError::MissingSession);
        };
        if call.call_id != call_id || call.phase != CallPhase::Ringing {
            return Err(PrivateDmRuntimeError::MissingSession);
        }
        call.become_active(now_ms());
        // The caller keeps re-offering until it sees this accept. If the
        // accept never left, the local state must go back to ringing so the
        // next offer re-triggers the accept path instead of the state
        // machine rejecting the retry as "no longer ringing".
        if let Err(error) = self.publish_call_accept(call_id) {
            if let Some(call) = self.call.as_mut() {
                call.phase = CallPhase::Ringing;
                call.started_at_ms = 0;
            }
            return Err(error);
        }
        Ok(())
    }

    /// Retransmits the ring while the caller waits, and gives up once the ring
    /// budget is spent. Driven by the same ~1s drain tick as `pump_handshake`.
    pub(super) fn pump_call_signaling(&mut self, now_ms: u64) {
        let Some(call) = self.call.as_ref() else {
            return;
        };
        if call.phase != CallPhase::Outgoing {
            return;
        }
        let call_id = call.call_id.clone();
        if now_ms.saturating_sub(call.offer_first_ms) >= CALL_RING_TIMEOUT_MS {
            let _ = self.call_end(&call_id, "no_answer");
            return;
        }
        if now_ms.saturating_sub(call.offer_last_ms) < CALL_RESEND_MS {
            return;
        }
        let key_b64 = call.key_b64.clone();
        let nonce_prefix_b64 = call.nonce_prefix_b64.clone();
        match self.publish_call_offer(&call_id, &key_b64, &nonce_prefix_b64) {
            // A failed send must not burn the slot: retry on the next tick.
            Err(error) => dlog::write(
                LogLevel::Error,
                kinds::CALL,
                call_id.as_str(),
                &format!("call offer resend failed: {error}"),
            ),
            Ok(()) => {
                if let Some(call) = self.call.as_mut() {
                    call.mark_offer_sent(now_ms);
                }
            }
        }
    }

    pub(super) fn call_decline(
        &mut self,
        call_id: &str,
        reason: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        let Some(call) = self.call.as_ref() else {
            return Ok(());
        };
        if call.call_id != call_id {
            return Ok(());
        }
        let envelope = ControlEnvelope::CallDecline {
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            call_id: call_id.to_string(),
            reason: reason.to_string(),
        };
        // Publish BEFORE clearing: a decline that never left leaves the
        // peer ringing against a call we consider gone, and a cleared slot
        // has no path to re-send. On failure the call stays held so the
        // user can decline (or answer) again on the next try.
        self.send_call_control(&envelope)?;
        self.finish_call("missed", 0);
        Ok(())
    }

    pub(super) fn call_end(
        &mut self,
        call_id: &str,
        reason: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        let Some(call) = self.call.as_ref() else {
            return Ok(());
        };
        if call.call_id != call_id {
            return Ok(());
        }
        let duration = call.duration_ms(now_ms());
        let kind = call.end_kind();
        self.finish_call(kind, duration);
        let envelope = ControlEnvelope::CallEnd {
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            call_id: call_id.to_string(),
            reason: reason.to_string(),
        };
        self.send_call_control(&envelope)
    }
}

impl PrivateDmRuntime {
    pub fn call_start(&mut self, session_id: &str) -> Result<CallStarted, PrivateDmRuntimeError> {
        self.drain_inbound();
        self.session_mut(session_id)?.call_start()
    }

    pub fn call_accept(
        &mut self,
        session_id: &str,
        call_id: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        self.drain_inbound();
        let outcome = self.session_mut(session_id)?.call_accept(call_id);
        self.sync_call_media();
        outcome
    }

    pub fn call_decline(
        &mut self,
        session_id: &str,
        call_id: &str,
        reason: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        self.drain_inbound();
        let outcome = self.session_mut(session_id)?.call_decline(call_id, reason);
        self.sync_call_media();
        outcome
    }

    pub fn call_end(
        &mut self,
        session_id: &str,
        call_id: &str,
        reason: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        self.drain_inbound();
        let outcome = self.session_mut(session_id)?.call_end(call_id, reason);
        self.sync_call_media();
        outcome
    }
}

impl PrivateDmSession {
    /// The Call* control frames. Anything else is an unknown control kind and
    /// is dropped, which is what an older build does with a frame it does not
    /// know.
    pub(super) fn handle_call_control(
        &mut self,
        envelope: ControlEnvelope,
    ) -> Result<(), PrivateDmRuntimeError> {
        match envelope {
            ControlEnvelope::CallOffer {
                session_id,
                participant_id,
                from_device,
                call_id,
                offer_ciphertext_b64,
            } if self.is_from_counterpart(&session_id, &participant_id) => {
                self.handle_call_offer(from_device, call_id, &offer_ciphertext_b64)
            }
            ControlEnvelope::CallAccept {
                session_id,
                participant_id,
                call_id,
            } if self.is_from_counterpart(&session_id, &participant_id) => {
                if let Some(call) = self.call.as_mut() {
                    if call.call_id == call_id && call.phase == CallPhase::Outgoing {
                        call.become_active(now_ms());
                    }
                }
                Ok(())
            }
            ControlEnvelope::CallDecline {
                session_id,
                participant_id,
                call_id,
                reason: _,
            } if self.is_from_counterpart(&session_id, &participant_id) => {
                if self.holds_call(&call_id) {
                    self.finish_call("missed", 0);
                }
                Ok(())
            }
            ControlEnvelope::CallEnd {
                session_id,
                participant_id,
                call_id,
                reason: _,
            } if self.is_from_counterpart(&session_id, &participant_id) => {
                if let Some(call) = self.call.as_ref().filter(|call| call.call_id == call_id) {
                    let duration = call.duration_ms(now_ms());
                    let kind = call.end_kind();
                    self.finish_call(kind, duration);
                }
                Ok(())
            }
            _ => Ok(()),
        }
    }

    pub(super) fn holds_call(&self, call_id: &str) -> bool {
        self.call
            .as_ref()
            .is_some_and(|call| call.call_id == call_id)
    }

    /// An incoming ring. The caller re-offers until it sees our CallAccept,
    /// so a re-offer of the call we already answered means that accept was
    /// dropped: re-send it, or the caller rings out against a callee sitting
    /// in an active call. Any other offer while a call is held is ignored.
    pub(super) fn handle_call_offer(
        &mut self,
        from_device: String,
        call_id: String,
        offer_ciphertext_b64: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        if let Some(existing) = self.call.as_ref() {
            if existing.call_id == call_id && existing.phase == CallPhase::Active {
                return self.publish_call_accept(&call_id);
            }
            return Ok(());
        }
        let plaintext = self.crypto.decrypt(&decode(offer_ciphertext_b64)?)?;
        let body: CallOfferBody = decode_json(&plaintext)?;
        self.note_authenticated_frame(&from_device);
        let channel = voice_call_channel(&call_id);
        self.call = Some(CallState::ringing(
            call_id,
            body.key_b64,
            body.nonce_prefix_b64,
            from_device,
        ));
        // The media channel is the whole point of the ring: without the
        // subscription every later frame for this call is lost, and the
        // stored ring would ignore repeated offers (any other offer while a
        // call is held is a no-op). Roll the ring back so the next offer
        // starts over from a clean slot.
        match self.transport.subscribe(&self.mesh_id, &channel) {
            Ok(()) => Ok(()),
            Err(_) => {
                let _ = self.call.take();
                Err(PrivateDmRuntimeError::Moss(
                    "voice call channel subscribe failed".to_string(),
                ))
            }
        }
    }

    /// Drop the call we hold, leave its channel, and log it in the history.
    pub(super) fn finish_call(&mut self, kind: &str, duration_ms: u64) {
        let Some(call) = self.call.take() else {
            return;
        };
        let _ = self
            .transport
            .unsubscribe(&self.mesh_id, &voice_call_channel(&call.call_id));
        self.append_call_event_message(&call.remote_device, kind, duration_ms, &call.call_id);
    }

    pub(super) fn append_call_event_message(
        &mut self,
        remote_device: &str,
        kind: &str,
        duration_ms: u64,
        call_id: &str,
    ) {
        let message = self.messages.stamp(ChatMessage {
            from_device: remote_device.to_string(),
            body: String::new(),
            message_id: None,
            sent_at_ms: None,
            attachment: None,
            call_event: Some(CallEvent {
                kind: kind.to_string(),
                duration_ms,
                call_id: call_id.to_string(),
            }),
            delivery_status: None,
            delivery_error: None,
            retryable: None,
            retry_count: None,
            read: None,
        });
        self.messages.push(message);
    }
}
