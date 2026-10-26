//! Original issuer associations bind an Add to the exact pinned Welcome.
use super::*;
use crate::mls_crypto::MlsHistoryContext;
use crate::mls_crypto::StagedAdmission;
use crate::persistence::history_admission::EvidenceWrite;
use crate::sender_auth::{SenderProof, VerifiedSender};
use sha2::{Digest, Sha256};

pub(super) type Association = (
    String,
    u8,
    String,
    String,
    Option<String>,
    String,
    (u64, String),
    (u64, String),
    String,
    String,
    String,
    String,
    Option<String>,
    u64,
);

impl GroupSession {
    pub(in crate::private_group_runtime) fn verify_joiner_binding(
        &self,
        proof: &SenderProof,
        package: &[u8],
    ) -> Result<VerifiedSender, PrivateGroupError> {
        let sender = proof
            .verify(&OrgContext {
                org_pubkey: self.org_pubkey.as_deref().unwrap_or(""),
                mesh_id: &self.mesh_id,
                channel_kind: &self.control_channel,
            })
            .map_err(PrivateGroupError::Codec)?;
        let expected = key_package_input(
            &self.to_persisted_record(),
            package,
            &self.crypto.key_package_signer(package)?,
            &sender.peer_id,
        )?;
        if sender.payload != expected
            || hex::encode(&sender.mls_signer) != self.crypto.key_package_signer(package)?
        {
            return Err(PrivateGroupError::Codec(
                "joiner binding differs from actual KeyPackage".into(),
            ));
        }
        Ok(sender)
    }

    pub(in crate::private_group_runtime) fn admit_history_member(
        &mut self,
        participant: String,
        package: &[u8],
        joiner: Option<&SenderProof>,
        own_fp: String,
    ) -> Result<(), PrivateGroupError> {
        let prior = self.crypto.history_context()?;
        let mut candidate = self.crypto.receive_candidate()?;
        let outcome = if self.org_pubkey.is_some() {
            candidate.replace_member(&self.crypto.key_package_identity(package)?, package)?
        } else {
            candidate.add_members(&[package])?
        };
        let next = candidate.history_context()?;
        let binding = self.issue_admission_binding(&prior, &next, &outcome, package, joiner)?;
        let replay =
            self.prepare_admission_replay(&outcome, participant, own_fp, binding.clone())?;
        let replay_key = self.admission_replay_key(package);
        self.persist_own_admission(
            &candidate,
            &outcome,
            &binding,
            joiner,
            super::welcome::replay_write(&replay_key, &replay)?,
        )?;
        self.crypto = candidate;
        self.log_commit(prior.epoch, &outcome.commit_bytes);
        self.retain_admission_replay(replay_key, replay.clone());
        self.publish_admission_replay(&replay)
    }

    fn issue_admission_binding(
        &self,
        prior: &MlsHistoryContext,
        next: &MlsHistoryContext,
        outcome: &AddOutcome,
        package: &[u8],
        joiner: Option<&SenderProof>,
    ) -> Result<SenderProof, PrivateGroupError> {
        let input = (
            "mosh-history-admission-association-v1",
            1u8,
            &self.deletions.context,
            &self.mesh_id,
            &self.org_pubkey,
            hex::encode(&prior.group_id),
            (prior.epoch, &prior.hash),
            (next.epoch, &next.hash),
            hex::encode(Sha256::digest(&outcome.commit_bytes)),
            hex::encode(Sha256::digest(&outcome.welcome_bytes)),
            hex::encode(Sha256::digest(&outcome.tree_bytes)),
            self.crypto.key_package_signer(package)?,
            joiner
                .map(serde_json::to_vec)
                .transpose()
                .map_err(|e| PrivateGroupError::Codec(e.to_string()))?
                .map(|b| hex::encode(Sha256::digest(b))),
            now_ms(),
        );
        self.sign_application(&input, &self.control_channel)
    }

    fn persist_own_admission(
        &self,
        candidate: &MlsSessionCrypto,
        outcome: &AddOutcome,
        binding: &SenderProof,
        joiner: Option<&SenderProof>,
        replay: EvidenceWrite,
    ) -> Result<(), PrivateGroupError> {
        let Some(store) = self.persistence.as_deref() else {
            return Ok(());
        };
        let prior = self.crypto.history_context()?;
        let next = candidate.history_context()?;
        let prefix = format!(
            "group/{}",
            hex::encode(Sha256::digest(self.group_id.as_bytes()))
        );
        let mut evidence = vec![
            replay,
            EvidenceWrite {
                key: format!(
                    "{prefix}/evidence/admission-association/{}",
                    hex::encode(Sha256::digest(&outcome.commit_bytes))
                ),
                bytes: serde_json::to_vec(binding)
                    .map_err(|e| PrivateGroupError::Codec(e.to_string()))?,
            },
        ];
        if let Some(joiner) = joiner {
            let bytes =
                serde_json::to_vec(joiner).map_err(|e| PrivateGroupError::Codec(e.to_string()))?;
            evidence.push(EvidenceWrite {
                key: format!(
                    "{prefix}/evidence/joiner/{}",
                    hex::encode(Sha256::digest(&bytes))
                ),
                bytes,
            });
        }
        evidence.push(super::transitions::transition_write(
            super::transitions::TransitionState {
                previous: &self.crypto,
                next: candidate,
                prior: &prior,
                context: &next,
                author: &self.crypto.signer_public(),
                removed: false,
            },
            &self.group_id,
            &outcome.commit_bytes,
        )?);
        store.commit_history_admission::<GroupMessage>(
            GROUP_HISTORY,
            &self.group_id,
            HistoryAdmission {
                own_snapshot: Some(&candidate.snapshot()),
                evidence: &evidence,
                org_authority: self.org_history_guard(&self.device_fingerprint, true)?,
                ..Default::default()
            },
            &[],
        )?;
        Ok(())
    }

    pub(in crate::private_group_runtime) fn verify_admission_association(
        &self,
        proof: &SenderProof,
        staged: &StagedAdmission,
        welcome: &str,
        tree: &str,
        commit: &str,
    ) -> Result<(), PrivateGroupError> {
        let sender = proof
            .verify(&OrgContext {
                org_pubkey: self.org_pubkey.as_deref().unwrap_or(""),
                mesh_id: &self.mesh_id,
                channel_kind: &self.control_channel,
            })
            .map_err(PrivateGroupError::Codec)?;
        let binding: Association = decode_json(&sender.payload)?;
        if let Some(expected) = &binding.12 {
            let package = self
                .pending_join_package
                .as_ref()
                .ok_or(PrivateGroupError::NotReady)?;
            let own = joiner_binding(
                &self.node,
                &self.crypto,
                &self.to_persisted_record(),
                package,
            )?;
            let bytes =
                serde_json::to_vec(&own).map_err(|e| PrivateGroupError::Codec(e.to_string()))?;
            if *expected != hex::encode(Sha256::digest(bytes)) {
                return Err(PrivateGroupError::Codec(
                    "admission joiner proof differs".into(),
                ));
            }
        }
        let (group, epoch) = MlsSessionCrypto::admission_commit_header(&decode(commit)?)?;
        if binding.0 != "mosh-history-admission-association-v1"
            || binding.1 != 1
            || binding.2 != self.deletions.context
            || binding.3 != self.mesh_id
            || binding.4 != self.org_pubkey
            || binding.5 != hex::encode(&group)
            || group != staged.context.group_id
            || binding.6 .0 != epoch
            || epoch.checked_add(1) != Some(staged.context.epoch)
            || binding.7 != (staged.context.epoch, staged.context.hash.clone())
            || binding.8 != digest(commit)?
            || binding.9 != digest(welcome)?
            || binding.10 != digest(tree)?
            || binding.11 != hex::encode(staged.next.signer_public())
            || sender.mls_signer != staged.author
            || (self.org_pubkey.is_some() && sender.peer_id != staged.author_identity)
        {
            return Err(PrivateGroupError::Codec(
                "admission association differs from pinned Welcome".into(),
            ));
        }
        Ok(())
    }
}

fn digest(encoded: &str) -> Result<String, PrivateGroupError> {
    Ok(hex::encode(Sha256::digest(decode(encoded)?)))
}

pub(in crate::private_group_runtime) fn joiner_binding(
    node: &MossNode,
    crypto: &MlsSessionCrypto,
    record: &PersistedGroupSession,
    package: &[u8],
) -> Result<SenderProof, PrivateGroupError> {
    let identity = node
        .identity_signer()
        .map_err(|e| PrivateGroupError::Moss(e.to_string()))?;
    let moss_key = hex::encode(identity.verifying_key().to_bytes());
    SenderProof::sign(
        identity,
        crypto,
        &OrgContext {
            org_pubkey: record.org_pubkey.as_deref().unwrap_or(""),
            mesh_id: &record.mesh_id,
            channel_kind: &format!("{CONTROL_CHANNEL_PREFIX}{}", record.group_id),
        },
        key_package_input(
            record,
            package,
            &hex::encode(crypto.signer_public()),
            &moss_key,
        )?,
    )
    .map_err(PrivateGroupError::Codec)
}

fn key_package_input(
    record: &PersistedGroupSession,
    package: &[u8],
    mls: &str,
    moss: &str,
) -> Result<Vec<u8>, PrivateGroupError> {
    serde_json::to_vec(&(
        "mosh-history-key-package-v1",
        1u8,
        format!("group:{}", record.group_id),
        &record.mesh_id,
        &record.org_pubkey,
        hex::encode(Sha256::digest(package)),
        mls,
        moss,
    ))
    .map_err(|e| PrivateGroupError::Codec(e.to_string()))
}
