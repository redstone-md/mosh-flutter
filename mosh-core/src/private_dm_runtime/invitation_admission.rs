//! First counterpart admission must be durable before its Welcome leaves.
use super::*;

impl PrivateDmSession {
    pub(super) fn admit_invitation_package(
        &mut self,
        name: &str,
        moss: Option<String>,
        package: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        let signer = self.crypto.key_package_signer(&decode(package)?)?;
        self.check_invitation_signer(&signer)?;
        // A package retry proves its MLS signer, not its cleartext name or
        // Moss route. Established contact metadata changes only on authenticated
        // conversation traffic, including when legacy records lack a signer pin.
        if self.peer_joined {
            return self.answer_key_package(package);
        }
        let previous_name = self.peer_display_name.clone();
        let previous_moss = self.peer_moss_id.clone();
        let previous_dirty = self.record_dirty;
        self.note_peer_name(name);
        self.note_peer_moss_id(moss);
        let result = self.answer_key_package(package);
        if result.is_err()
            && !self
                .invitation
                .as_ref()
                .is_some_and(|invite| invite.consumed)
        {
            self.peer_display_name = previous_name;
            self.peer_moss_id = previous_moss;
            self.record_dirty = previous_dirty;
        }
        result
    }

    fn check_invitation_signer(&self, signer: &str) -> Result<(), PrivateDmRuntimeError> {
        let pinned = self
            .invitation
            .as_ref()
            .and_then(|invite| invite.admitted_signer.as_deref());
        let rejected = pinned.map_or_else(
            || self.peer_joined && !self.is_existing_counterpart_signer(signer),
            |expected| expected != signer,
        );
        if rejected {
            return Err(PrivateDmRuntimeError::InvalidInvite(
                "invitation already used".into(),
            ));
        }
        Ok(())
    }

    fn is_existing_counterpart_signer(&self, signer: &str) -> bool {
        signer != hex::encode(self.crypto.signer_public())
            && self
                .crypto
                .member_signers()
                .iter()
                .any(|member| member == signer)
            && self
                .membership
                .as_ref()
                .is_none_or(|membership| membership.has_counterpart(&[signer.to_owned()]))
    }
    pub(super) fn unwrap_invitation_admission(
        &self,
        envelope: ControlEnvelope,
    ) -> Result<ControlEnvelope, PrivateDmRuntimeError> {
        match envelope {
            ControlEnvelope::InvitationKeyPackage {
                session_id,
                invitation_token,
                payload_b64,
            } => {
                if session_id != self.session_id {
                    return Err(PrivateDmRuntimeError::InvalidInvite(
                        "wrong invitation session".into(),
                    ));
                }
                self.verify_admission_token(Some(&invitation_token))?;
                let inner = decode_json(&decode(&payload_b64)?)?;
                if !matches!(
                    inner,
                    ControlEnvelope::KeyPackage { .. }
                        | ControlEnvelope::AuthenticatedKeyPackage { .. }
                ) {
                    return Err(PrivateDmRuntimeError::InvalidInvite(
                        "invitation requires a KeyPackage".into(),
                    ));
                }
                Ok(inner)
            }
            ControlEnvelope::KeyPackage { .. }
            | ControlEnvelope::AuthenticatedKeyPackage { .. } => {
                self.verify_admission_token(None)?;
                Ok(envelope)
            }
            other => Ok(other),
        }
    }

    /// A repeated package gets only its original Welcome. A different MLS
    /// signer can never consume a used invitation, including after restart.
    pub(super) fn answer_key_package(
        &mut self,
        key_package_b64: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        let package = decode(key_package_b64)?;
        let signer = self.crypto.key_package_signer(&package)?;
        if self.peer_joined {
            self.check_invitation_signer(&signer)?;
            return self.pending_welcome.as_ref().map_or(Ok(()), |payload| {
                self.route_send(ChannelKind::Control, payload)
            });
        }
        let snapshot = self.crypto.snapshot();
        let group_id = self.crypto.group_id_bytes().unwrap_or_default();
        let previous_invitation = self.invitation.clone();
        let previous_state = self.state;
        let payload = self.prepare_invitation_welcome(&package, signer)?;
        if let Some(store) = &self.device_store {
            if let Err(error) = self.write_extra(store) {
                self.crypto = MlsSessionCrypto::restore(
                    &self.device_id,
                    &self.crypto.signer_public(),
                    &snapshot,
                    &group_id,
                )?;
                self.invitation = previous_invitation;
                self.state = previous_state;
                self.peer_joined = false;
                self.pending_welcome = None;
                return Err(error.into());
            }
        }
        self.record_dirty = true;
        self.route_send(ChannelKind::Control, &payload)
    }

    fn prepare_invitation_welcome(
        &mut self,
        package: &[u8],
        signer: String,
    ) -> Result<Vec<u8>, PrivateDmRuntimeError> {
        let (welcome, tree) = self.crypto.add_peer(package)?;
        self.note_handshake_frame();
        let envelope = ControlEnvelope::Welcome {
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            from_device: self.device_id.clone(),
            welcome_b64: encode(&welcome),
            ratchet_tree_b64: encode(&tree),
            moss_peer_id: self.transport.local_peer_id(),
        };
        let payload = serde_json::to_vec(&envelope)
            .map_err(|error| PrivateDmRuntimeError::Codec(error.to_string()))?;
        let invitation = self
            .invitation
            .get_or_insert_with(|| invitations::InviteLifecycle::new(true));
        invitation.consumed = true;
        invitation.admitted_signer = Some(signer);
        invitation.peer_name = self.peer_display_name.clone();
        invitation.welcome_payload = Some(payload.clone());
        self.pending_welcome = Some(payload.clone());
        Ok(payload)
    }
}
