//! Protected native receive facts. These are not remotely accepted receipts.
use super::membership::MembershipReference;
use super::receipts::AcceptanceEvidenceV1;
use super::*;
use crate::conversation::recovery::GroupAcceptanceBasis;
use crate::mls_crypto::MlsHistoryContext;
use crate::persistence::history_admission::EvidenceWrite;
use crate::sender_auth::VerifiedSender;
use sha2::{Digest, Sha256};

#[derive(Clone, Serialize, Deserialize)]
pub(in crate::private_group_runtime) struct NativeAcceptance {
    pub(in crate::private_group_runtime) record_hash: String,
    pub(in crate::private_group_runtime) original_sender_proof_b64: String,
    pub(in crate::private_group_runtime) original_author_mls_key: String,
    pub(in crate::private_group_runtime) original_author_moss_key: String,
    pub(in crate::private_group_runtime) origin: Option<crate::message_deletion::MessageOrigin>,
    pub(in crate::private_group_runtime) context: MlsHistoryContext,
    pub(in crate::private_group_runtime) author_admission_instance: Option<MembershipReference>,
    pub(super) receipt: Option<AcceptanceEvidenceV1>,
    original_org_roster_b64: Option<String>,
    pub(super) basis: GroupAcceptanceBasis,
    #[serde(skip)]
    pub(super) offer: Option<AttachmentOffer>,
}

pub(in crate::private_group_runtime) fn native_acceptance_key(group: &str, id: &str) -> String {
    format!(
        "group/{}/local-acceptance/{}",
        hex::encode(Sha256::digest(group.as_bytes())),
        hex::encode(Sha256::digest(id.as_bytes())),
    )
}

impl NativeAcceptance {
    pub(super) fn text(
        session: &GroupSession,
        message: &GroupMessage,
        sender: &VerifiedSender,
        proof: &[u8],
    ) -> Result<(Self, Vec<EvidenceWrite>), PrivateGroupError> {
        Self::create(session, message, sender, proof, &session.data_channel, None)
    }

    pub(in crate::private_group_runtime) fn attachment(
        session: &GroupSession,
        message: &GroupMessage,
        sender: &VerifiedSender,
        proof: &[u8],
        offer: AttachmentOffer,
    ) -> Result<(Self, Vec<EvidenceWrite>), PrivateGroupError> {
        Self::create(
            session,
            message,
            sender,
            proof,
            &session.control_channel,
            Some(offer),
        )
    }

    fn create(
        session: &GroupSession,
        message: &GroupMessage,
        sender: &VerifiedSender,
        proof: &[u8],
        channel: &str,
        offer: Option<AttachmentOffer>,
    ) -> Result<(Self, Vec<EvidenceWrite>), PrivateGroupError> {
        let membership = session.native_membership_checkpoint(sender, proof, channel)?;
        let (admission, writes) = membership
            .map(|m| (Some(m.reference), m.writes))
            .unwrap_or_default();
        let mut accepted = Self {
            record_hash: semantic_record_hash(
                &session.deletions.context,
                &session.mesh_id,
                message,
                &hex::encode(&sender.mls_signer),
                &sender.peer_id,
                offer.as_ref(),
            )?,
            original_sender_proof_b64: encode(proof),
            original_author_mls_key: hex::encode(&sender.mls_signer),
            original_author_moss_key: sender.peer_id.clone(),
            origin: message.metadata.as_ref().and_then(|m| m.origin.clone()),
            context: session.crypto.history_context()?,
            // A verified-since checkpoint is explicitly distinct from a
            // missing canonical Add; it never grants earlier entitlement.
            author_admission_instance: admission,
            receipt: None,
            original_org_roster_b64: session
                .org_history_guard(&sender.peer_id, false)?
                .map(|guard| encode(guard.roster_bytes)),
            basis: GroupAcceptanceBasis::LiveAuthenticated,
            offer,
        };
        accepted.receipt = AcceptanceEvidenceV1::native(session, &accepted)?;
        Ok((accepted, writes))
    }

    pub(super) fn first_write(
        &mut self,
        store: &Persistence,
        key: String,
        already_held: bool,
        group_id: &str,
    ) -> Result<Vec<EvidenceWrite>, PrivateGroupError> {
        if let Some(retained) = store.group_history_evidence::<Self>(&key)? {
            if retained.record_hash != self.record_hash {
                return Err(PrivateGroupError::Codec(
                    "conflicting accepted group text".into(),
                ));
            }
            let offer = self.offer.take();
            *self = retained;
            self.offer = offer;
            return Ok(Vec::new());
        }
        if already_held {
            // Existing imports/legacy rows retain their original provenance.
            return Ok(Vec::new());
        }
        let mut writes = vec![EvidenceWrite {
            key,
            bytes: serde_json::to_vec(self)
                .map_err(|error| PrivateGroupError::Codec(error.to_string()))?,
        }];
        if let Some(receipt) = &self.receipt {
            writes.push(EvidenceWrite {
                key: format!(
                    "group/{}/evidence/acceptance/{}",
                    hex::encode(Sha256::digest(group_id.as_bytes())),
                    receipt.hash()?
                ),
                bytes: serde_json::to_vec(receipt)
                    .map_err(|error| PrivateGroupError::Codec(error.to_string()))?,
            });
        }
        Ok(writes)
    }
}

pub(super) fn semantic_record_hash(
    context: &str,
    mesh_id: &str,
    message: &GroupMessage,
    author_mls_key: &str,
    author_moss_key: &str,
    offer: Option<&AttachmentOffer>,
) -> Result<String, PrivateGroupError> {
    let origin = message.metadata.as_ref().and_then(|m| m.origin.as_ref());
    let origin_hash = origin
        .map(crate::conversation::recovery::manifest::digest)
        .transpose()
        .map_err(PrivateGroupError::Codec)?;
    let occurrence = origin
        .map(|origin| origin.key())
        .transpose()
        .map_err(PrivateGroupError::Codec)?;
    let mut hash = Sha256::new();
    hash.update(b"mosh-history-record-binding-v1\0");
    hash.update(
        serde_json::to_vec(&(
            context,
            mesh_id,
            occurrence,
            &message.message_id,
            if offer.is_some() {
                "attachment_offer"
            } else {
                "text"
            },
            hex::encode(Sha256::digest(if let Some(offer) = offer {
                serde_json::to_vec(offer).map_err(|e| PrivateGroupError::Codec(e.to_string()))?
            } else {
                message.body.as_bytes().to_vec()
            })),
            origin_hash,
            Option::<String>::None,
            author_mls_key,
            Some(author_moss_key),
            message.sent_at_ms,
            &message.from_device,
        ))
        .map_err(|error| PrivateGroupError::Codec(error.to_string()))?,
    );
    Ok(hex::encode(hash.finalize()))
}
