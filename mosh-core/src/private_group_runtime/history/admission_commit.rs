//! Queued signed associations remain untrusted until our own staged Add verifies.
use super::*;
use crate::mls_crypto::StagedMembership;
use crate::persistence::history_admission::EvidenceWrite;
use crate::sender_auth::SenderProof;
use sha2::{Digest, Sha256};

#[derive(Serialize, Deserialize)]
struct PendingAssociation {
    conversation: String,
    mesh: String,
    org: Option<String>,
    proof: SenderProof,
    original_org: Option<String>,
    roster: Option<String>,
}

impl GroupSession {
    pub(in crate::private_group_runtime) fn retain_admission_association(
        &self,
        commit: &str,
        proof: &SenderProof,
    ) -> Result<(), PrivateGroupError> {
        let sender = proof
            .verify(&OrgContext {
                org_pubkey: self.org_pubkey.as_deref().unwrap_or(""),
                mesh_id: &self.mesh_id,
                channel_kind: &self.control_channel,
            })
            .map_err(PrivateGroupError::Codec)?;
        let association: super::admission::Association = decode_json(&sender.payload)?;
        if association.0 != "mosh-history-admission-association-v1"
            || association.1 != 1
            || association.2 != self.deletions.context
            || association.3 != self.mesh_id
            || association.4 != self.org_pubkey
            || association.8 != hex::encode(Sha256::digest(decode(commit)?))
        {
            return Err(PrivateGroupError::Codec(
                "commit admission scope differs".into(),
            ));
        }
        let Some(store) = self.persistence.as_deref() else {
            return Ok(());
        };
        let pending = PendingAssociation {
            conversation: self.deletions.context.clone(),
            mesh: self.mesh_id.clone(),
            org: self.org_pubkey.clone(),
            proof: proof.clone(),
            original_org: self.incoming_org_control.as_ref().map(|b| encode(b)),
            roster: self.roster_cache.as_ref().map(|r| encode(&r.0)),
        };
        store.commit_history_admission::<GroupMessage>(
            GROUP_HISTORY,
            &self.group_id,
            HistoryAdmission {
                evidence: &[EvidenceWrite {
                    key: pending_key(&self.group_id, &decode(commit)?),
                    bytes: serde_json::to_vec(&pending)
                        .map_err(|e| PrivateGroupError::Codec(e.to_string()))?,
                }],
                ..Default::default()
            },
            &[],
        )?;
        Ok(())
    }
}

pub(super) fn verified_association(
    store: &Persistence,
    group: &str,
    prior: &MlsSessionCrypto,
    staged: &StagedMembership,
    commit: &[u8],
) -> Result<Vec<EvidenceWrite>, PrivateGroupError> {
    let Some(pending) =
        store.group_history_evidence::<PendingAssociation>(&pending_key(group, commit))?
    else {
        return Ok(Vec::new());
    };
    let sender = pending
        .proof
        .verify(&OrgContext {
            org_pubkey: pending.org.as_deref().unwrap_or(""),
            mesh_id: &pending.mesh,
            channel_kind: &format!("{CONTROL_CHANNEL_PREFIX}{group}"),
        })
        .map_err(PrivateGroupError::Codec)?;
    let binding: super::admission::Association = decode_json(&sender.payload)?;
    if pending.conversation != format!("group:{group}")
        || binding.2 != pending.conversation
        || binding.3 != pending.mesh
        || binding.4 != pending.org
        || binding.5 != hex::encode(&staged.prior.group_id)
        || binding.6 != (staged.prior.epoch, staged.prior.hash.clone())
        || binding.7 != (staged.context.epoch, staged.context.hash.clone())
        || binding.8 != hex::encode(Sha256::digest(commit))
        || sender.mls_signer != staged.author
        || prior.member_signers().contains(&binding.11)
        || !staged.next.member_signers().contains(&binding.11)
    {
        return Err(PrivateGroupError::Codec(
            "admission differs from own verified transition".into(),
        ));
    }
    Ok(vec![EvidenceWrite {
        key: format!(
            "group/{}/evidence/admission-association/{}",
            hex::encode(Sha256::digest(group.as_bytes())),
            binding.8
        ),
        bytes: serde_json::to_vec(&pending).map_err(|e| PrivateGroupError::Codec(e.to_string()))?,
    }])
}

fn pending_key(group: &str, commit: &[u8]) -> String {
    format!(
        "group/{}/pending-association/{}",
        hex::encode(Sha256::digest(group.as_bytes())),
        hex::encode(Sha256::digest(commit))
    )
}
