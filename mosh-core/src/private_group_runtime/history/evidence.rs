//! Protected native receive facts. These are not remotely accepted receipts.
use super::membership::MembershipReference;
use super::*;
use crate::conversation::recovery::GroupAcceptanceBasis;
use crate::mls_crypto::MlsHistoryContext;
use crate::persistence::history_admission::EvidenceWrite;
use crate::sender_auth::VerifiedSender;
use sha2::{Digest, Sha256};

#[derive(Serialize, Deserialize)]
pub(in crate::private_group_runtime) struct NativeAcceptance {
    pub(in crate::private_group_runtime) record_hash: String,
    pub(in crate::private_group_runtime) original_sender_proof_b64: String,
    pub(in crate::private_group_runtime) original_author_mls_key: String,
    pub(in crate::private_group_runtime) original_author_moss_key: String,
    pub(in crate::private_group_runtime) origin: Option<crate::message_deletion::MessageOrigin>,
    pub(in crate::private_group_runtime) context: MlsHistoryContext,
    pub(in crate::private_group_runtime) author_admission_instance: Option<MembershipReference>,
    original_org_roster_b64: Option<String>,
    basis: GroupAcceptanceBasis,
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
        let (admission, writes) =
            session.native_membership_checkpoint(sender, proof, &session.data_channel)?;
        Ok((
            Self {
                record_hash: text_record_hash(session, message, sender)?,
                original_sender_proof_b64: encode(proof),
                original_author_mls_key: hex::encode(&sender.mls_signer),
                original_author_moss_key: sender.peer_id.clone(),
                origin: message.metadata.as_ref().and_then(|m| m.origin.clone()),
                context: session.crypto.history_context()?,
                // A verified-since checkpoint is explicitly distinct from a
                // missing canonical Add; it never grants earlier entitlement.
                author_admission_instance: admission,
                original_org_roster_b64: session
                    .org_history_guard(&sender.peer_id, false)?
                    .map(|guard| encode(guard.roster_bytes)),
                basis: GroupAcceptanceBasis::LiveAuthenticated,
            },
            writes,
        ))
    }

    pub(super) fn first_write(
        &self,
        store: &Persistence,
        key: String,
        already_held: bool,
    ) -> Result<Vec<EvidenceWrite>, PrivateGroupError> {
        if let Some(retained) = store.group_history_evidence::<Self>(&key)? {
            if retained.record_hash != self.record_hash {
                return Err(PrivateGroupError::Codec(
                    "conflicting accepted group text".into(),
                ));
            }
            return Ok(Vec::new());
        }
        if already_held {
            // Existing imports/legacy rows retain their original provenance.
            return Ok(Vec::new());
        }
        Ok(vec![EvidenceWrite {
            key,
            bytes: serde_json::to_vec(self)
                .map_err(|error| PrivateGroupError::Codec(error.to_string()))?,
        }])
    }
}

fn text_record_hash(
    session: &GroupSession,
    message: &GroupMessage,
    sender: &VerifiedSender,
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
            &session.deletions.context,
            &session.mesh_id,
            occurrence,
            &message.message_id,
            "text",
            hex::encode(Sha256::digest(message.body.as_bytes())),
            origin_hash,
            Option::<String>::None,
            hex::encode(&sender.mls_signer),
            Some(&sender.peer_id),
            message.sent_at_ms,
            &message.from_device,
        ))
        .map_err(|error| PrivateGroupError::Codec(error.to_string()))?,
    );
    Ok(hex::encode(hash.finalize()))
}
