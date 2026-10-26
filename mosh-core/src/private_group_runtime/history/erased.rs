//! Erased frozen slots retain hashes and verified tombstones, never deleted bytes or keys.
use super::records::GroupRecord;
use super::*;
use crate::message_deletion::{DeleteScope, DeletionRecord};
use crate::sender_auth::{SenderProof, VerifiedSender};

#[derive(Clone, Serialize, Deserialize)]
pub(super) struct ErasedTarget {
    pub(super) attachment: bool,
    deletion_key: String,
}

impl GroupSession {
    pub(super) fn erased_history_target(
        &mut self,
        row: &StoredMessage<GroupMessage>,
        accepted: &NativeAcceptance,
    ) -> Result<ErasedTarget, PrivateGroupError> {
        let origin = row
            .message
            .metadata
            .as_ref()
            .and_then(|metadata| metadata.origin.as_ref())
            .ok_or(PrivateGroupError::NotReady)?;
        let authority = self.deletion_authority()?;
        let deletion = self
            .deletions
            .records
            .values()
            .find(|record| {
                record.scope == DeleteScope::ForEveryone
                    && record
                        .request
                        .as_ref()
                        .is_some_and(|request| request.target == *origin)
                    && authority.validate(record, &authority.local.key).is_ok()
            })
            .cloned()
            .ok_or(PrivateGroupError::NotReady)?;
        self.publish_deletion(&crate::message_deletion::protocol::DeletionMessage::State {
            records: vec![deletion.clone()],
            next: None,
        })?;
        let proof: SenderProof = decode_json(&decode(&accepted.original_sender_proof_b64)?)?;
        let attachment = proof
            .verify(&OrgContext {
                org_pubkey: self.org_pubkey.as_deref().unwrap_or(""),
                mesh_id: &self.mesh_id,
                channel_kind: &self.control_channel,
            })
            .is_ok();
        Ok(ErasedTarget {
            deletion_key: deletion.key.clone(),
            attachment,
        })
    }

    pub(super) fn history_record_erasure(
        &mut self,
        record: &GroupRecord,
        holder: &str,
    ) -> Result<Option<DeletionRecord>, PrivateGroupError> {
        let Some(erased) = &record.erased else {
            return Ok(None);
        };
        let authority = self.deletion_authority()?;
        self.deletions
            .records
            .values()
            .find(|deletion| {
                deletion.key == erased.deletion_key
                    && deletion.scope == DeleteScope::ForEveryone
                    && deletion.request.as_ref().is_some_and(|request| {
                        Some(&request.target) == record.acceptance.origin.as_ref()
                    })
                    && authority.validate(deletion, holder).is_ok()
            })
            .cloned()
            .map(Some)
            .ok_or_else(|| {
                PrivateGroupError::Codec("erased group target awaits verified deletion".into())
            })
    }
}

impl GroupRecord {
    pub(super) fn verify_erased_original(
        &self,
        session: &GroupSession,
    ) -> Result<VerifiedSender, PrivateGroupError> {
        let author = self.verify_original_author(session)?;
        let origin = self
            .acceptance
            .origin
            .as_ref()
            .ok_or(PrivateGroupError::NotReady)?;
        origin
            .verify_signature()
            .map_err(PrivateGroupError::Codec)?;
        if !self.body.is_empty()
            || self.offer.is_some()
            || origin.id != self.message_id
            || origin.conversation != session.deletions.context
            || origin.author != hex::encode(&author.mls_signer)
        {
            return Err(PrivateGroupError::Codec(
                "erased group original binding differs".into(),
            ));
        }
        let erased = self.erased.as_ref().ok_or(PrivateGroupError::NotReady)?;
        if erased.attachment {
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
            {
                return Err(PrivateGroupError::NotReady);
            }
        } else {
            let envelope: DataEnvelope = decode_json(&author.payload)?;
            if envelope.group_id != session.group_id
                || envelope.message_id.as_deref() != Some(&self.message_id)
                || envelope.sent_at_ms != Some(self.sent_at_ms)
                || envelope.from_device != self.from_device
                || envelope.from_fingerprint != author.peer_id
                || envelope.origin.as_ref() != Some(origin)
            {
                return Err(PrivateGroupError::NotReady);
            }
        }
        Ok(author)
    }
}
