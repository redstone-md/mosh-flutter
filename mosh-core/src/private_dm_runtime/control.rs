//! The control channel: handshake, receipts, and call signaling envelopes.

use super::*;

impl PrivateDmSession {
    pub(super) fn handle_control(&mut self, payload: Vec<u8>) -> Result<(), PrivateDmRuntimeError> {
        let envelope: ControlEnvelope = decode_json(&payload)?;

        match envelope {
            ControlEnvelope::KeyPackage {
                session_id,
                participant_id,
                from_device,
                key_package_b64,
                moss_peer_id,
            } if self.is_alice_session(&session_id, &participant_id) => {
                self.note_peer_name(&from_device);
                self.note_peer_moss_id(moss_peer_id);
                self.answer_key_package(&key_package_b64)
            }
            ControlEnvelope::Welcome {
                session_id,
                participant_id,
                from_device,
                welcome_b64,
                ratchet_tree_b64,
                moss_peer_id,
            } if self.is_bob_session(&session_id, &participant_id) => {
                if self.peer_joined {
                    return Ok(());
                }
                self.note_peer_name(&from_device);
                self.note_peer_moss_id(moss_peer_id);
                self.crypto
                    .join_welcome(&decode(&welcome_b64)?, &decode(&ratchet_tree_b64)?)?;
                self.note_handshake_frame();
                // Joined: stop retransmitting the KeyPackage.
                self.pending_key_package = None;
                Ok(())
            }
            ControlEnvelope::Hello {
                session_id,
                participant_id,
                from_device,
                hello_ciphertext_b64,
            } if self.is_from_counterpart(&session_id, &participant_id) => {
                // Decrypting authenticates: only the MLS peer can produce a
                // ciphertext this group accepts.
                let Ok(plaintext) = self.crypto.decrypt(&decode(&hello_ciphertext_b64)?) else {
                    dlog::write(
                        LogLevel::Warn,
                        kinds::HANDSHAKE,
                        &session_id,
                        "dropping unverifiable hello",
                    );
                    return Ok(());
                };
                if let Ok(moss_peer_id) = String::from_utf8(plaintext) {
                    self.note_peer_moss_id(Some(moss_peer_id));
                }
                self.note_authenticated_frame(&from_device);
                // Answer so the sender gets its proof too, but not inside
                // our own cadence: two Connected sides would otherwise
                // ping-pong hellos forever.
                let now = now_ms();
                if now.saturating_sub(self.last_hello_send_ms) >= HANDSHAKE_RESEND_MS {
                    self.send_hello(now);
                }
                Ok(())
            }
            ControlEnvelope::DeliveryAck {
                session_id,
                participant_id,
                ack_ciphertext_b64,
            } if self.is_from_counterpart(&session_id, &participant_id) => {
                // Decrypting authenticates: only the MLS peer can produce a
                // ciphertext this group accepts. Forged or garbled acks stop
                // here and the resend loop keeps running.
                let Ok(ciphertext) = decode(&ack_ciphertext_b64) else {
                    return Ok(());
                };
                let Ok(plaintext) = self.crypto.decrypt(&ciphertext) else {
                    dlog::write(
                        LogLevel::Warn,
                        kinds::DELIVERY,
                        &session_id,
                        "dropping unverifiable delivery ack",
                    );
                    return Ok(());
                };
                let Ok(message_id) = String::from_utf8(plaintext) else {
                    return Ok(());
                };
                self.note_authenticated_frame("");
                // The peer's runtime holds the message: settle it as
                // Delivered and stop the auto-resend loop. Unknown ids (ack
                // for an attempt a restart already dropped) are ignored.
                if let Some(attempt) = self.outbound_attempts.remove(&message_id) {
                    self.messages.mark_delivery(
                        &message_id,
                        MessageDeliveryStatus::Delivered,
                        None,
                        attempt.retry_count,
                    )?;
                    self.dirty_outbound.push(message_id.clone());
                    // Session transition the field log carries: the
                    // counterpart's ack settled the message as delivered.
                    dlog::write(
                        LogLevel::Info,
                        kinds::DELIVERY,
                        &self.session_id,
                        &format!("message {message_id} settled delivered"),
                    );
                }
                Ok(())
            }
            ControlEnvelope::TypingIndicator {
                session_id,
                participant_id,
                from_device,
                typing_ciphertext_b64,
            } if self.is_from_counterpart(&session_id, &participant_id) => {
                // Decrypting authenticates: only the MLS peer can produce a
                // ciphertext this group accepts, so a forged hint stops here
                // and the session keeps quiet.
                let Ok(ciphertext) = decode(&typing_ciphertext_b64) else {
                    return Ok(());
                };
                let Ok(plaintext) = self.crypto.decrypt(&ciphertext) else {
                    dlog::write(
                        LogLevel::Warn,
                        kinds::VERIFY,
                        &session_id,
                        "dropping unverifiable typing hint",
                    );
                    return Ok(());
                };
                // The body names the device, but the authenticated identity is
                // the envelope's `from_device` + the fact it decrypted; accept
                // the body only when it agrees.
                if let Ok(body) = decode_json::<TypingBody>(&plaintext) {
                    self.note_peer_name(&from_device);
                    if body.device != from_device {
                        return Ok(());
                    }
                }
                self.note_authenticated_frame(&from_device);
                self.note_peer_typing(now_ms());
                Ok(())
            }
            ControlEnvelope::AttachmentManifest {
                session_id,
                participant_id,
                from_device,
                manifest_ciphertext_b64,
            } if self.is_from_counterpart(&session_id, &participant_id) => {
                let manifest_json = self.crypto.decrypt(&decode(&manifest_ciphertext_b64)?)?;
                let manifest: AttachmentManifest = decode_json(&manifest_json)?;
                self.note_authenticated_frame(&from_device);
                self.accept_incoming_manifest(from_device, manifest)
            }
            ControlEnvelope::ReadReceipt {
                session_id,
                participant_id,
                receipt_ciphertext_b64,
            } if self.is_from_counterpart(&session_id, &participant_id) => {
                // Decrypting authenticates: only the MLS peer can produce a
                // ciphertext this group accepts, so a forged receipt stops
                // here and the ticks keep their color. The symmetry rule
                // lives in the runtime: when this user does not send
                // receipts, the inbound ones are dropped unread.
                let Some(true) =
                    crate::read_receipts::load(&crate::api::shared_runtime::resolved_data_dir())
                        .map(|setting| setting.enabled)
                else {
                    return Ok(());
                };
                let Ok(ciphertext) = decode(&receipt_ciphertext_b64) else {
                    return Ok(());
                };
                let Ok(plaintext) = self.crypto.decrypt(&ciphertext) else {
                    dlog::write(
                        LogLevel::Warn,
                        kinds::VERIFY,
                        &session_id,
                        "dropping unverifiable read receipt",
                    );
                    return Ok(());
                };
                let Ok(body) = decode_json::<ReadReceiptBody>(&plaintext) else {
                    return Ok(());
                };
                self.note_authenticated_frame("");
                self.note_peer_read(&body.message_id);
                Ok(())
            }
            ControlEnvelope::PeerAnnounce {
                session_id,
                participant_id,
                from_device,
                moss_peer_id,
            } if self.is_from_counterpart(&session_id, &participant_id) => {
                let was_unknown = self.peer_moss_id.is_none();
                self.note_peer_name(&from_device);
                self.note_peer_moss_id(Some(moss_peer_id));
                // Answer once, and only to an announce that told us something
                // new: the peer announces because IT is missing our id, and
                // without this reply a pair that both restarted would each wait
                // for the other. Answering unconditionally would instead ping-
                // pong forever between two sides that already know each other.
                if was_unknown {
                    let _ = self.publish_peer_announce();
                }
                Ok(())
            }
            other => self.handle_call_control(other),
        }
    }

    /// Alice's side of the handshake. Bob re-sends his KeyPackage until he
    /// sees the Welcome; if we already added him, our first Welcome was
    /// likely lost before his node meshed, so re-answer with the cached copy
    /// rather than calling add_members again (which advances the group
    /// epoch).
    pub(super) fn answer_key_package(
        &mut self,
        key_package_b64: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        if self.peer_joined {
            if let Some(welcome_payload) = self.pending_welcome.clone() {
                return self.route_send(ChannelKind::Control, &welcome_payload);
            }
            return Ok(());
        }
        let key_package = decode(key_package_b64)?;
        let (welcome, tree) = self.crypto.add_peer(&key_package)?;
        self.note_handshake_frame();
        let envelope = ControlEnvelope::Welcome {
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            from_device: self.device_id.clone(),
            welcome_b64: encode(&welcome),
            ratchet_tree_b64: encode(&tree),
            moss_peer_id: self.transport.local_peer_id(),
        };
        let welcome_payload = serde_json::to_vec(&envelope)
            .map_err(|error| PrivateDmRuntimeError::Codec(error.to_string()))?;
        self.pending_welcome = Some(welcome_payload.clone());
        self.route_send(ChannelKind::Control, &welcome_payload)
    }

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
        self.transport
            .subscribe(&self.mesh_id, &channel)
            .map_err(PrivateDmRuntimeError::Moss)
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
