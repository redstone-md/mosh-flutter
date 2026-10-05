//! The control channel: handshake, receipts, and call signaling envelopes.

use super::*;

mod feedback;

#[cfg(test)]
#[path = "welcome_auth_tests.rs"]
mod welcome_auth_tests;

impl PrivateDmSession {
    pub(super) fn handle_control(&mut self, payload: Vec<u8>) -> Result<(), PrivateDmRuntimeError> {
        let envelope: ControlEnvelope = decode_json(&payload)?;
        if let ControlEnvelope::MessageDeletion { session_id, frame } = envelope {
            return if session_id == self.session_id {
                self.receive_deletion_frame(frame)
            } else {
                Ok(())
            };
        }

        self.handle_handshake_control(envelope)
    }

    fn handle_handshake_control(
        &mut self,
        envelope: ControlEnvelope,
    ) -> Result<(), PrivateDmRuntimeError> {
        match envelope {
            ControlEnvelope::AuthenticatedKeyPackage {
                session_id,
                proof_b64,
            } if session_id == self.session_id && matches!(self.role, SessionRole::Alice) => {
                self.accept_authenticated_key_package(&proof_b64)
            }
            ControlEnvelope::DeviceIdentity {
                session_id,
                participant_id,
                ciphertext_b64,
            } if self.is_from_counterpart(&session_id, &participant_id) => {
                self.accept_identity_claim(&ciphertext_b64)
            }
            ControlEnvelope::KeyPackage {
                session_id,
                participant_id,
                from_device,
                key_package_b64,
                moss_peer_id,
            } if self.is_alice_session(&session_id, &participant_id) => {
                self.accept_legacy_key_package(&from_device, moss_peer_id, &key_package_b64)
            }
            ControlEnvelope::Welcome {
                session_id,
                participant_id,
                from_device,
                welcome_b64,
                ratchet_tree_b64,
                moss_peer_id,
            } if self.is_bob_session(&session_id, &participant_id) => {
                self.accept_welcome(&welcome_b64, &ratchet_tree_b64, &from_device, moss_peer_id)
            }
            ControlEnvelope::Hello {
                session_id,
                participant_id,
                from_device,
                hello_ciphertext_b64,
            } if self.is_from_counterpart(&session_id, &participant_id) => {
                self.accept_hello(&hello_ciphertext_b64, &from_device)
            }
            other => self.handle_feedback_control(other),
        }
    }

    fn accept_legacy_key_package(
        &mut self,
        name: &str,
        moss_peer_id: Option<String>,
        key_package: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        if self.expected_invitee()?.is_some() {
            return Err(PrivateDmRuntimeError::InvalidInvite(
                "targeted DM requires authenticated admission".into(),
            ));
        }
        self.note_peer_name(name);
        self.note_peer_moss_id(moss_peer_id);
        self.answer_key_package(key_package)
    }

    fn handle_feedback_control(
        &mut self,
        envelope: ControlEnvelope,
    ) -> Result<(), PrivateDmRuntimeError> {
        match envelope {
            ControlEnvelope::DeliveryAck {
                session_id,
                participant_id,
                ack_ciphertext_b64,
            } if self.is_from_counterpart(&session_id, &participant_id) => {
                self.accept_delivery_ack(&ack_ciphertext_b64)
            }
            ControlEnvelope::TypingIndicator {
                session_id,
                participant_id,
                from_device,
                typing_ciphertext_b64,
            } if self.is_from_counterpart(&session_id, &participant_id) => {
                self.accept_typing_hint(&typing_ciphertext_b64, &from_device)
            }
            ControlEnvelope::AttachmentManifest {
                session_id,
                participant_id,
                from_device,
                manifest_ciphertext_b64,
            } if self.is_from_counterpart(&session_id, &participant_id) => {
                self.accept_verified_attachment(from_device, &manifest_ciphertext_b64)
            }
            ControlEnvelope::ReadReceipt {
                session_id,
                participant_id,
                receipt_ciphertext_b64,
            } if self.is_from_counterpart(&session_id, &participant_id) => {
                self.accept_read_receipt(&receipt_ciphertext_b64)
            }
            ControlEnvelope::PeerAnnounce {
                session_id,
                participant_id,
                from_device,
                moss_peer_id,
            } if self.is_from_counterpart(&session_id, &participant_id) => {
                self.accept_peer_announce(&from_device, moss_peer_id)
            }
            other => self.handle_call_control(other),
        }
    }

    fn accept_verified_attachment(
        &mut self,
        from_device: String,
        ciphertext: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        let context = format!("dm:{}", self.session_id);
        let (body, _) = self
            .crypto
            .decrypt_checked(&decode(ciphertext)?, |body, signer| {
                let manifest: AttachmentOffer =
                    serde_json::from_slice(body).map_err(|e| e.to_string())?;
                manifest.verify(&context, Some(signer))?;
                Ok(())
            })?;
        let manifest: AttachmentOffer = decode_json(&body)?;
        self.note_authenticated_frame(&from_device);
        self.accept_incoming_manifest(from_device, manifest)
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

    fn accept_welcome(
        &mut self,
        welcome_b64: &str,
        ratchet_tree_b64: &str,
        _from_device: &str,
        moss_peer_id: Option<String>,
    ) -> Result<(), PrivateDmRuntimeError> {
        // A linked client accepts only its authorized private admission.
        if self
            .membership
            .as_ref()
            .is_some_and(|membership| membership.is_joining())
        {
            return Ok(());
        }
        if self.peer_joined {
            return Ok(());
        }
        let owner = self
            .invite_uri
            .as_deref()
            .map(|raw| {
                let invite = ParsedInvite::parse(raw)?;
                invite_ownership::verify_invite_owner(raw, &invite)
                    .map_err(PrivateDmRuntimeError::InvalidInvite)
            })
            .transpose()?
            .flatten();
        let name = self.crypto.join_welcome_pinned(
            &decode(welcome_b64)?,
            &decode(ratchet_tree_b64)?,
            &self.fingerprint,
            owner.as_ref().map(|owner| owner.mls_signer.as_slice()),
            None,
        )?;
        self.note_peer_name(&name);
        self.note_peer_moss_id(owner.map(|owner| owner.peer_id).or(moss_peer_id));
        self.note_handshake_frame();
        // Joined: stop retransmitting the KeyPackage.
        self.pending_key_package = None;
        Ok(())
    }
    fn accept_hello(
        &mut self,
        hello_ciphertext_b64: &str,
        from_device: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        // Decrypting authenticates: only the MLS peer can produce a
        // ciphertext this group accepts.
        // The MLS error names the cause (a replay of an already read
        // message, a stale epoch, a forgery); it carries no key
        // material.
        let (plaintext, from_device) =
            match self.decrypt_contact_control(&decode(hello_ciphertext_b64)?, from_device) {
                Ok(Some(result)) => result,
                Ok(None) => return Ok(()),
                Err(error) => {
                    dlog::write(
                        LogLevel::Warn,
                        kinds::HANDSHAKE,
                        &self.session_id,
                        &format!("dropping unverifiable hello: {error}"),
                    );
                    return Ok(());
                }
            };
        if let Ok(moss_peer_id) = String::from_utf8(plaintext) {
            self.note_peer_moss_id(Some(moss_peer_id));
        }
        self.note_authenticated_frame(&from_device);
        // The sender needs our proof too; the tick answers
        // (`pump_hello`).
        self.hello_answer_due = true;
        Ok(())
    }
    fn accept_delivery_ack(
        &mut self,
        ack_ciphertext_b64: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        // Decrypting authenticates: only the MLS peer can produce a
        // ciphertext this group accepts. Forged or garbled acks stop
        // here and the resend loop keeps running.
        let Ok(ciphertext) = decode(ack_ciphertext_b64) else {
            return Ok(());
        };
        let Ok((plaintext, signer)) = self.crypto.decrypt_with_signer(&ciphertext) else {
            dlog::write(
                LogLevel::Warn,
                kinds::DELIVERY,
                &self.session_id,
                "dropping unverifiable delivery ack",
            );
            return Ok(());
        };
        let Ok(message_id) = String::from_utf8(plaintext) else {
            return Ok(());
        };
        if self.devices_live() {
            return self.accept_device_receipt(&message_id, &signer);
        }
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
    fn accept_typing_hint(
        &mut self,
        typing_ciphertext_b64: &str,
        from_device: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        // Decrypting authenticates: only the MLS peer can produce a
        // ciphertext this group accepts, so a forged hint stops here
        // and the session keeps quiet.
        let Ok(ciphertext) = decode(typing_ciphertext_b64) else {
            return Ok(());
        };
        let Ok(frame) = self.decrypt_contact_control(&ciphertext, from_device) else {
            dlog::write(
                LogLevel::Warn,
                kinds::VERIFY,
                &self.session_id,
                "dropping unverifiable typing hint",
            );
            return Ok(());
        };
        let Some((plaintext, author)) = frame else {
            return Ok(());
        };
        // Keep legacy body/envelope agreement; MLS determines the contact.
        if let Ok(body) = decode_json::<TypingBody>(&plaintext) {
            self.note_peer_name(&author);
            if body.device != from_device {
                return Ok(());
            }
        }
        self.note_authenticated_frame(&author);
        self.note_peer_typing(now_ms());
        Ok(())
    }
}
