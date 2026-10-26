//! Semantic group records carry original proofs, never another leaf's ratchet.
use super::*;
use super::{
    evidence::semantic_record_hash, membership::NativeCheckpoint, protocol::GroupScope,
    vouches::HolderVouchV1,
};
use crate::conversation::{
    history::StoredMessage,
    recovery::{manifest::HistoryKey, occurrence::Occurrence},
};
use crate::sender_auth::VerifiedSender;
use sha2::{Digest, Sha256};

#[derive(Clone, Serialize, Deserialize)]
pub(super) struct GroupRecord {
    pub(super) message_id: String,
    pub(super) sent_at_ms: u64,
    pub(super) from_device: String,
    pub(super) body: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) offer: Option<AttachmentOffer>,
    pub(super) acceptance: NativeAcceptance,
    pub(super) author_checkpoint: NativeCheckpoint,
    pub(super) vouch: HolderVouchV1,
}

impl GroupSession {
    pub(super) fn retained_history_record(
        &mut self,
        row: &StoredMessage<GroupMessage>,
        recipient: &GroupScope,
        peer: &str,
    ) -> Result<GroupRecord, PrivateGroupError> {
        let store = self
            .persistence
            .as_ref()
            .ok_or(PrivateGroupError::NotReady)?;
        let acceptance: NativeAcceptance = store
            .group_history_evidence(&native_acceptance_key(&self.group_id, &row.message_id))?
            .ok_or_else(|| {
                PrivateGroupError::Codec("original group acceptance unavailable".into())
            })?;
        if row
            .message
            .metadata
            .as_ref()
            .is_some_and(|m| m.deletion.is_some())
        {
            return Err(PrivateGroupError::Codec(
                "group erased evidence unavailable".into(),
            ));
        }
        let reference = acceptance
            .author_admission_instance
            .as_ref()
            .ok_or(PrivateGroupError::NotReady)?;
        let author_checkpoint = store
            .group_history_evidence(&format!(
                "group/{}/evidence/membership/{}",
                hex::encode(Sha256::digest(self.group_id.as_bytes())),
                reference.tuple().1
            ))?
            .ok_or(PrivateGroupError::NotReady)?;
        let vouch = HolderVouchV1::issue(self, &acceptance, recipient, peer)?;
        let record = GroupRecord {
            message_id: row.message_id.clone(),
            sent_at_ms: row.sent_at_ms,
            from_device: row.message.from_device.clone(),
            body: row.message.body.clone(),
            offer: row
                .attachment_manifest
                .clone()
                .map(|manifest| AttachmentOffer {
                    manifest,
                    preview_manifest: row.preview_manifest.clone(),
                }),
            acceptance,
            author_checkpoint,
            vouch,
        };
        record.verify_original(self)?;
        Ok(record)
    }
}

impl GroupRecord {
    pub(super) fn key(
        row: &StoredMessage<GroupMessage>,
        context: &str,
        mesh: &str,
    ) -> Result<Option<HistoryKey>, String> {
        if row.message.name_change.is_some()
            || matches!(
                row.message.delivery_status,
                Some(MessageDeliveryStatus::Failed | MessageDeliveryStatus::Pending)
            )
        {
            return Ok(None);
        }
        if row
            .message
            .metadata
            .as_ref()
            .is_some_and(|m| m.deletion.is_some())
        {
            return Err("group erased evidence unavailable".into());
        }
        let offer = row
            .attachment_manifest
            .clone()
            .map(|manifest| AttachmentOffer {
                manifest,
                preview_manifest: row.preview_manifest.clone(),
            });
        if row.message.attachment.is_some() && offer.is_none() {
            return Err("attachment manifest unavailable".into());
        }
        let origin = row
            .message
            .metadata
            .as_ref()
            .and_then(|m| m.origin.as_ref())
            .ok_or("group original evidence unavailable")?;
        let digest = semantic_record_hash(
            context,
            mesh,
            &row.message,
            &origin.author,
            &row.message.from_fingerprint,
            offer.as_ref(),
        )
        .map_err(|e| e.to_string())?;
        Ok(Some(HistoryKey {
            message_id: row.message_id.clone(),
            sent_at_ms: row.sent_at_ms,
            digest,
        }))
    }

    pub(super) fn occurrence(
        row: &StoredMessage<GroupMessage>,
        context: &str,
        mesh: &str,
    ) -> Result<Option<Occurrence>, String> {
        let Some(key) = Self::key(row, context, mesh)? else {
            return Ok(None);
        };
        let origin = row
            .message
            .metadata
            .as_ref()
            .and_then(|m| m.origin.as_ref())
            .ok_or("group original evidence unavailable")?;
        Ok(Some(Occurrence {
            native_id: row.message_id.clone(),
            row_key: format!(
                "{}\u{1}{:020}\u{1}{}",
                row.conversation_id, row.sent_at_ms, row.message_id
            ),
            identity: origin.key()?,
            content_digest: Some(key.digest),
        }))
    }

    pub(super) fn verify_original(
        &self,
        session: &mut GroupSession,
    ) -> Result<(), PrivateGroupError> {
        if self.message_id.is_empty()
            || self.message_id.len() > 256
            || self.body.len() > MAX_BODY_LEN
            || self.from_device.len() > 1024
        {
            return Err(PrivateGroupError::Codec(
                "invalid group history record bounds".into(),
            ));
        }
        let author = self.verify_original_content(session)?;
        let member = self
            .author_checkpoint
            .verify_at(session, &self.acceptance.context)?;
        if member.peer_id != author.peer_id
            || member.mls_signer != author.mls_signer
            || Some(&self.author_checkpoint.reference()?)
                != self.acceptance.author_admission_instance.as_ref()
            || self.acceptance.context != *self.author_checkpoint.context()
            || semantic_record_hash(
                &session.deletions.context,
                &session.mesh_id,
                &self.message(),
                &self.acceptance.original_author_mls_key,
                &self.acceptance.original_author_moss_key,
                self.offer.as_ref(),
            )? != self.acceptance.record_hash
        {
            return Err(PrivateGroupError::Codec(
                "group historical author interval differs".into(),
            ));
        }
        self.acceptance
            .receipt
            .as_ref()
            .ok_or(PrivateGroupError::NotReady)?
            .verify(&self.acceptance)
    }

    pub(super) fn verify(
        &self,
        session: &mut GroupSession,
        holder: &VerifiedSender,
    ) -> Result<(), PrivateGroupError> {
        self.verify_original(session)?;
        self.vouch.verify(session, &self.acceptance, holder)
    }

    pub(super) fn message(&self) -> GroupMessage {
        GroupMessage {
            metadata: Some(crate::message_deletion::MessageMetadata {
                origin: self.acceptance.origin.clone(),
                is_own: Some(false),
                ..Default::default()
            }),
            from_device: self.from_device.clone(),
            from_fingerprint: self.acceptance.original_author_moss_key.clone(),
            body: self.body.clone(),
            message_id: Some(self.message_id.clone()),
            sent_at_ms: Some(self.sent_at_ms),
            attachment: self
                .offer
                .as_ref()
                .map(|o| crate::conversation::attachments::descriptor_of(&o.manifest)),
            delivery_status: None,
            delivery_error: None,
            retryable: None,
            retry_count: None,
            name_change: None,
        }
    }
}
