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
        let (
            domain,
            version,
            conversation,
            mesh,
            org,
            _group_id,
            _prior_context,
            _next_context,
            commit_hash,
            _welcome_hash,
            _tree_hash,
            _admitted_key,
            _joiner_proof_hash,
            _claimed_at,
        ): super::admission::Association = decode_json(&sender.payload)?;
        if domain != "mosh-history-admission-association-v1"
            || version != 1
            || conversation != self.deletions.context
            || mesh != self.mesh_id
            || org != self.org_pubkey
            || commit_hash != hex::encode(Sha256::digest(decode(commit)?))
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
        store.save_pending_group_evidence(
            &format!(
                "group/{}/pending-association/",
                hex::encode(Sha256::digest(self.group_id.as_bytes()))
            ),
            &pending_key(&self.group_id, &decode(commit)?, &sender.mls_signer),
            &serde_json::to_vec(&pending).map_err(|e| PrivateGroupError::Codec(e.to_string()))?,
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
    let Some(pending) = store.group_history_evidence::<PendingAssociation>(&pending_key(
        group,
        commit,
        &staged.author,
    ))?
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
    let (
        _domain,
        _version,
        conversation,
        mesh,
        org,
        group_id,
        prior_context,
        next_context,
        commit_hash,
        _welcome_hash,
        _tree_hash,
        admitted_key,
        _joiner_proof_hash,
        _claimed_at,
    ): super::admission::Association = decode_json(&sender.payload)?;
    if pending.conversation != format!("group:{group}")
        || conversation != pending.conversation
        || mesh != pending.mesh
        || org != pending.org
        || group_id != hex::encode(&staged.prior.group_id)
        || prior_context != (staged.prior.epoch, staged.prior.hash.clone())
        || next_context != (staged.context.epoch, staged.context.hash.clone())
        || commit_hash != hex::encode(Sha256::digest(commit))
        || sender.mls_signer != staged.author
        || prior.member_signers().contains(&admitted_key)
        || !staged.next.member_signers().contains(&admitted_key)
    {
        return Err(PrivateGroupError::Codec(
            "admission differs from own verified transition".into(),
        ));
    }
    Ok(vec![EvidenceWrite {
        key: format!(
            "group/{}/evidence/admission-association/{}",
            hex::encode(Sha256::digest(group.as_bytes())),
            commit_hash
        ),
        bytes: serde_json::to_vec(&pending).map_err(|e| PrivateGroupError::Codec(e.to_string()))?,
    }])
}

fn pending_key(group: &str, commit: &[u8], author: &[u8]) -> String {
    format!(
        "group/{}/pending-association/{}/{}",
        hex::encode(Sha256::digest(group.as_bytes())),
        hex::encode(Sha256::digest(commit)),
        hex::encode(author)
    )
}
