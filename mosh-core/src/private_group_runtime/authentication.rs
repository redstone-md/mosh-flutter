//! Authenticate every application representation through the same boundary.
use super::*;
use crate::sender_auth::{SenderProof, VerifiedSender};

impl GroupSession {
    fn application_context<'a>(&'a self, channel: &'a str) -> OrgContext<'a> {
        OrgContext {
            org_pubkey: self.org_pubkey.as_deref().unwrap_or(""),
            mesh_id: &self.mesh_id,
            channel_kind: channel,
        }
    }

    pub(super) fn sign_application<T: Serialize>(
        &self,
        value: &T,
        channel: &str,
    ) -> Result<SenderProof, PrivateGroupError> {
        if !self.joined || !self.crypto.is_ready() {
            return Err(PrivateGroupError::NotReady);
        }
        let payload = serde_json::to_vec(value)
            .map_err(|error| PrivateGroupError::Codec(error.to_string()))?;
        SenderProof::sign(
            self.node
                .identity_signer()
                .map_err(|error| PrivateGroupError::Moss(error.to_string()))?,
            &self.crypto,
            &self.application_context(channel),
            payload,
        )
        .map_err(PrivateGroupError::Codec)
    }

    pub(super) fn verify_application(
        &mut self,
        proof: &SenderProof,
        channel: &str,
    ) -> Result<VerifiedSender, PrivateGroupError> {
        if !self.joined || !self.crypto.is_ready() {
            return Err(PrivateGroupError::NotReady);
        }
        let sender = proof
            .verify(&self.application_context(channel))
            .map_err(PrivateGroupError::Codec)?;
        let member = self.crypto.member_identity_for_signer(&sender.mls_signer);
        if member.is_none()
            || (self.org_pubkey.is_some()
                && (member.as_deref() != Some(&sender.peer_id)
                    || !self.roster_contains(&sender.peer_id)))
        {
            return Err(PrivateGroupError::Codec(
                "sender is not an authorized group member".into(),
            ));
        }
        Ok(sender)
    }

    pub(super) fn decrypt_application(
        &mut self,
        ciphertext: &str,
        sender: &VerifiedSender,
    ) -> Result<Vec<u8>, PrivateGroupError> {
        self.crypto
            .decrypt_from_signer(&decode(ciphertext)?, &sender.mls_signer)
            .map_err(Into::into)
    }

    pub(super) fn handle_authenticated_control(
        &mut self,
        proof: SenderProof,
    ) -> Result<(), PrivateGroupError> {
        let original_proof =
            serde_json::to_vec(&proof).map_err(|e| PrivateGroupError::Codec(e.to_string()))?;
        let sender = self.verify_application(&proof, &self.control_channel.clone())?;
        let envelope: ControlEnvelope = decode_json(&sender.payload)?;
        if envelope.group_id() != self.group_id {
            return Ok(());
        }
        match envelope {
            ControlEnvelope::History { frame, .. } => self.queue_history(frame, false),
            ControlEnvelope::PlusMetadata { frame, .. } => self.receive_plus(&frame, sender),
            ControlEnvelope::MessageDeletion { frame, .. } => {
                self.receive_deletion_frame(frame, &sender)
            }
            ControlEnvelope::NameMetadata {
                operation,
                epoch,
                ciphertext_b64,
                ..
            } => self.accept_name_metadata(operation, epoch, &ciphertext_b64, sender),
            envelope @ ControlEnvelope::AttachmentManifest { .. } => {
                self.accept_verified_manifest(envelope, sender, &original_proof)
            }
            ControlEnvelope::TypingIndicator {
                from_device,
                from_fingerprint,
                typing_ciphertext_b64,
                ..
            } => self.accept_verified_typing(
                &from_device,
                from_fingerprint,
                &typing_ciphertext_b64,
                sender,
            ),
            ControlEnvelope::DmOffer {
                offer_ciphertext_b64,
                ..
            } => self.accept_verified_offer(&offer_ciphertext_b64, sender),
            _ => Err(PrivateGroupError::Codec(
                "sender proof requires an application frame".into(),
            )),
        }
    }

    fn accept_verified_manifest(
        &mut self,
        envelope: ControlEnvelope,
        sender: VerifiedSender,
        original_proof: &[u8],
    ) -> Result<(), PrivateGroupError> {
        let ControlEnvelope::AttachmentManifest {
            participant_id,
            from_device,
            from_fingerprint,
            manifest_ciphertext_b64,
            sent_at_ms,
            ..
        } = envelope
        else {
            return Ok(());
        };
        if participant_id == self.participant_id {
            return Ok(());
        }
        self.require_author(&from_fingerprint, &sender)?;
        let context = format!("group:{}", self.group_id);
        let staged = self.crypto.stage_decrypt_checked(
            &decode(&manifest_ciphertext_b64)?,
            |body, signer| {
                if signer != sender.mls_signer {
                    return Err("group attachment signer mismatch".into());
                }
                let offer: AttachmentOffer =
                    serde_json::from_slice(body).map_err(|e| e.to_string())?;
                offer.verify(&context, Some(signer))?;
                if offer.manifest.from_fingerprint != sender.peer_id {
                    return Err("attachment author mismatch".into());
                }
                Ok(())
            },
        )?;
        let offer: AttachmentOffer = decode_json(&staged.body)?;
        let message = self.attachment_history_message(
            from_device,
            sender.peer_id.clone(),
            &offer,
            sent_at_ms,
        );
        let (accepted, evidence) = super::history::NativeAcceptance::attachment(
            self,
            &message,
            &sender,
            original_proof,
            offer.clone(),
        )?;
        self.persist_received(&staged, &message, accepted, evidence)?;
        self.crypto = staged.next;
        self.accept_incoming_manifest(message, offer)
    }

    fn accept_verified_typing(
        &mut self,
        name: &str,
        fingerprint: String,
        ciphertext: &str,
        sender: VerifiedSender,
    ) -> Result<(), PrivateGroupError> {
        self.require_author(&fingerprint, &sender)?;
        let body: GroupTypingBody = decode_json(&self.decrypt_application(ciphertext, &sender)?)?;
        if body.device != name {
            return Err(PrivateGroupError::Codec("typing name mismatch".into()));
        }
        self.note_member_typing(sender.peer_id, name, now_ms());
        Ok(())
    }

    fn accept_verified_offer(
        &mut self,
        ciphertext: &str,
        sender: VerifiedSender,
    ) -> Result<(), PrivateGroupError> {
        let mut offer: DmOffer = decode_json(&self.decrypt_application(ciphertext, &sender)?)?;
        self.require_author(&offer.from_fingerprint, &sender)?;
        crate::private_dm_runtime::invite_ownership::verify_offered_invite(
            &offer.invite_uri,
            &sender.peer_id,
            &offer.target_fingerprint,
        )
        .map_err(PrivateGroupError::Codec)?;
        offer.authenticated = Some(true);
        self.dm_offers.receive(offer, &self.device_fingerprint);
        Ok(())
    }

    pub(super) fn require_author(
        &self,
        claimed: &str,
        sender: &VerifiedSender,
    ) -> Result<(), PrivateGroupError> {
        if claimed != sender.peer_id {
            return Err(PrivateGroupError::Codec("sender identity mismatch".into()));
        }
        Ok(())
    }
}
