//! Checkpoints are born only from our durable verified tree and native key proofs.
use super::*;
use crate::mls_crypto::MlsHistoryContext;
use crate::persistence::history_admission::EvidenceWrite;
use crate::sender_auth::VerifiedSender;
use sha2::{Digest, Sha256};
mod canonical;
mod current;
mod own;

pub(super) struct NativeMembership {
    pub(super) reference: MembershipReference,
    pub(super) checkpoint: NativeCheckpoint,
    pub(super) writes: Vec<EvidenceWrite>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(in crate::private_group_runtime) enum MembershipReference {
    CommitV1(String),
    GenesisV1(String),
    VerifiedSinceCheckpointV1(String),
}

impl MembershipReference {
    pub(super) fn tuple(&self) -> (&str, &str) {
        match self {
            Self::CommitV1(id) => ("commit_v1", id),
            Self::GenesisV1(id) => ("genesis_v1", id),
            Self::VerifiedSinceCheckpointV1(id) => ("verified_since_checkpoint_v1", id),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct VerifiedSinceCheckpointV1 {
    conversation: String,
    mesh_id: String,
    context: MlsHistoryContext,
    mls_key: String,
    moss_key: String,
    binding_hash: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(in crate::private_group_runtime) struct NativeCheckpoint {
    checkpoint: VerifiedSinceCheckpointV1,
    binding_channel: String,
    original_binding_proof_b64: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    canonical_reference: Option<MembershipReference>,
}

impl VerifiedSinceCheckpointV1 {
    fn id(&self) -> Result<String, PrivateGroupError> {
        let mut hash = Sha256::new();
        hash.update(b"mosh-history-membership-checkpoint-v1\0");
        hash.update(
            serde_json::to_vec(&(
                &self.conversation,
                hex::encode(&self.context.group_id),
                &self.mesh_id,
                &self.context.hash,
                self.context.epoch,
                &self.mls_key,
                &self.moss_key,
                &self.binding_hash,
            ))
            .map_err(|error| PrivateGroupError::Codec(error.to_string()))?,
        );
        Ok(hex::encode(hash.finalize()))
    }
}

impl GroupSession {
    pub(super) fn native_membership_checkpoint(
        &self,
        sender: &VerifiedSender,
        proof: &[u8],
        channel: &str,
    ) -> Result<Option<NativeMembership>, PrivateGroupError> {
        let Some(store) = self.persistence.as_deref() else {
            return Ok(None);
        };
        let Some(mut context) = self.checkpoint_context(store, sender)? else {
            return Ok(None);
        };
        let canonical = self.canonical_membership(&context, &hex::encode(&sender.mls_signer))?;
        if let Some((_, start)) = &canonical {
            context = start.clone();
        }
        let key = format!(
            "group/{}/local-membership/{}/{}/{:020}/{}",
            hex::encode(Sha256::digest(self.group_id.as_bytes())),
            hex::encode(&sender.mls_signer),
            sender.peer_id,
            context.epoch,
            context.hash
        );
        if let Some(retained) = store.group_history_evidence::<NativeCheckpoint>(&key)? {
            return Ok(Some(NativeMembership {
                reference: retained.reference()?,
                checkpoint: retained,
                writes: Vec::new(),
            }));
        }
        let checkpoint = NativeCheckpoint {
            checkpoint: VerifiedSinceCheckpointV1 {
                conversation: self.deletions.context.clone(),
                mesh_id: self.mesh_id.clone(),
                context,
                mls_key: hex::encode(&sender.mls_signer),
                moss_key: sender.peer_id.clone(),
                binding_hash: hex::encode(Sha256::digest(proof)),
            },
            binding_channel: channel.into(),
            original_binding_proof_b64: encode(proof),
            canonical_reference: canonical.map(|(reference, _)| reference),
        };
        self.write_checkpoint(key, checkpoint)
    }

    fn checkpoint_context(
        &self,
        store: &Persistence,
        sender: &VerifiedSender,
    ) -> Result<Option<MlsHistoryContext>, PrivateGroupError> {
        let Some(snapshot) = store.get_group_mls_snapshot(&self.group_id)? else {
            return Ok(None);
        };
        let persisted = MlsSessionCrypto::restore(
            &self.display_name,
            &self.crypto.signer_public(),
            &snapshot,
            &self
                .crypto
                .group_id_bytes()
                .ok_or(PrivateGroupError::NotReady)?,
        )?;
        let context = self.crypto.history_context()?;
        if persisted.history_context()? != context
            || persisted
                .member_identity_for_signer(&sender.mls_signer)
                .is_none()
        {
            return Ok(None);
        }
        Ok(Some(context))
    }

    fn write_checkpoint(
        &self,
        key: String,
        checkpoint: NativeCheckpoint,
    ) -> Result<Option<NativeMembership>, PrivateGroupError> {
        let reference = checkpoint.reference()?;
        let id = reference.tuple().1;
        let bytes = serde_json::to_vec(&checkpoint)
            .map_err(|error| PrivateGroupError::Codec(error.to_string()))?;
        let public_key = format!(
            "group/{}/evidence/membership/{id}",
            hex::encode(Sha256::digest(self.group_id.as_bytes()))
        );
        Ok(Some(NativeMembership {
            reference,
            checkpoint,
            writes: vec![
                super::known_context::context_write(&self.group_id, &self.crypto)?,
                EvidenceWrite {
                    key,
                    bytes: bytes.clone(),
                },
                EvidenceWrite {
                    key: public_key,
                    bytes,
                },
            ],
        }))
    }
}
