//! Original author proof and complete semantic content survive every forwarder.
use super::records::GroupRecord;
use super::*;
use crate::sender_auth::{SenderProof, VerifiedSender};

impl GroupRecord {
    pub(super) fn verify_original_content(
        &self,
        session: &GroupSession,
    ) -> Result<VerifiedSender, PrivateGroupError> {
        let proof: SenderProof = decode_json(&decode(&self.acceptance.original_sender_proof_b64)?)?;
        let channel = if self.offer.is_some() {
            &session.control_channel
        } else {
            &session.data_channel
        };
        let author = proof
            .verify(&OrgContext {
                org_pubkey: session.org_pubkey.as_deref().unwrap_or(""),
                mesh_id: &session.mesh_id,
                channel_kind: channel,
            })
            .map_err(PrivateGroupError::Codec)?;
        if hex::encode(&author.mls_signer) != self.acceptance.original_author_mls_key
            || author.peer_id != self.acceptance.original_author_moss_key
        {
            return Err(PrivateGroupError::Codec(
                "original group author differs".into(),
            ));
        }
        if let Some(offer) = &self.offer {
            self.verify_original_offer(session, &author, offer)?;
        } else {
            self.verify_original_text(session, &author)?;
        }
        Ok(author)
    }

    fn verify_original_offer(
        &self,
        session: &GroupSession,
        author: &VerifiedSender,
        offer: &AttachmentOffer,
    ) -> Result<(), PrivateGroupError> {
        let ControlEnvelope::AttachmentManifest {
            group_id,
            from_device,
            from_fingerprint,
            sent_at_ms,
            ..
        } = decode_json(&author.payload)?
        else {
            return Err(PrivateGroupError::NotReady);
        };
        if group_id != session.group_id
            || from_device != self.from_device
            || from_fingerprint != author.peer_id
            || sent_at_ms.is_some_and(|time| time != self.sent_at_ms)
            || !self.body.is_empty()
            || offer.manifest.from_fingerprint != author.peer_id
            || offer.manifest.origin != self.acceptance.origin
            || offer
                .manifest
                .origin
                .as_ref()
                .is_none_or(|o| o.id != self.message_id)
        {
            return Err(PrivateGroupError::Codec(
                "original attachment binding differs".into(),
            ));
        }
        offer
            .verify(&session.deletions.context, Some(&author.mls_signer))
            .map_err(PrivateGroupError::Codec)
    }

    fn verify_original_text(
        &self,
        session: &GroupSession,
        author: &VerifiedSender,
    ) -> Result<(), PrivateGroupError> {
        let envelope: DataEnvelope = decode_json(&author.payload)?;
        if envelope.group_id != session.group_id
            || envelope.message_id.as_deref() != Some(&self.message_id)
            || envelope.sent_at_ms != Some(self.sent_at_ms)
            || envelope.from_device != self.from_device
            || envelope.from_fingerprint != author.peer_id
            || envelope.origin != self.acceptance.origin
        {
            return Err(PrivateGroupError::Codec(
                "original group record binding differs".into(),
            ));
        }
        self.acceptance
            .origin
            .as_ref()
            .ok_or(PrivateGroupError::NotReady)?
            .verify_from_signer(
                &session.deletions.context,
                &self.message_id,
                self.body.as_bytes(),
                &author.mls_signer,
            )
            .map_err(PrivateGroupError::Codec)
    }
}
