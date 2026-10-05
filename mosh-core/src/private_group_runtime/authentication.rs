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
        let sender = self.verify_application(&proof, &self.control_channel.clone())?;
        let envelope: ControlEnvelope = decode_json(&sender.payload)?;
        if envelope.group_id() != self.group_id {
            return Ok(());
        }
        match envelope {
            ControlEnvelope::MessageDeletion { frame, .. } => {
                self.receive_deletion_frame(frame, &sender)
            }
            ControlEnvelope::NameMetadata {
                operation,
                epoch,
                ciphertext_b64,
                ..
            } => self.accept_name_metadata(operation, epoch, &ciphertext_b64, sender),
            ControlEnvelope::AttachmentManifest {
                participant_id,
                from_device,
                from_fingerprint,
                manifest_ciphertext_b64,
                ..
            } if participant_id != self.participant_id => self.accept_verified_manifest(
                from_device,
                from_fingerprint,
                &manifest_ciphertext_b64,
                sender,
            ),
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
        name: String,
        fingerprint: String,
        ciphertext: &str,
        sender: VerifiedSender,
    ) -> Result<(), PrivateGroupError> {
        self.require_author(&fingerprint, &sender)?;
        let context = format!("group:{}", self.group_id);
        let (body, _) = self
            .crypto
            .decrypt_checked(&decode(ciphertext)?, |body, signer| {
                if signer != sender.mls_signer {
                    return Err("group attachment signer mismatch".into());
                }
                let manifest: AttachmentManifest =
                    serde_json::from_slice(body).map_err(|e| e.to_string())?;
                if let Some(origin) = &manifest.origin {
                    origin.verify_manifest_from_signer(&context, &manifest, signer)?;
                }
                if manifest.from_fingerprint != sender.peer_id {
                    return Err("attachment author mismatch".into());
                }
                Ok(())
            })?;
        let manifest: AttachmentManifest = decode_json(&body)?;
        self.require_author(&manifest.from_fingerprint, &sender)?;
        self.accept_incoming_manifest(name, sender.peer_id, manifest)
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
        let offer: DmOffer = decode_json(&self.decrypt_application(ciphertext, &sender)?)?;
        self.require_author(&offer.from_fingerprint, &sender)?;
        crate::private_dm_runtime::invite_ownership::verify_offered_invite(
            &offer.invite_uri,
            &sender.peer_id,
            &offer.target_fingerprint,
        )
        .map_err(PrivateGroupError::Codec)?;
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
