use super::DeletionError;
use crate::device_link::{account_certificate::AccountCertificate, identity::DeviceIdentity};
use crate::persistence::Persistence;
use ed25519_dalek::Signer;
use serde::{Deserialize, Serialize};
use std::sync::Arc;

#[derive(Serialize, Deserialize)]
struct AccountProof {
    certificate: AccountCertificate,
    subject: String,
    signature: String,
}

impl AccountProof {
    fn input(&self) -> Result<Vec<u8>, String> {
        let mut bytes = b"mosh-message-account-v1\0".to_vec();
        bytes.extend(
            serde_json::to_vec(&(&self.certificate, &self.subject)).map_err(|e| e.to_string())?,
        );
        Ok(bytes)
    }
    fn verify(&self, subject: &str) -> Result<(), String> {
        if self.subject != subject {
            return Err("account subject mismatch".into());
        }
        self.certificate.verify().map_err(|e| e.to_string())?;
        super::origin::verify_signature(self.certificate.subject(), &self.signature, &self.input()?)
    }
}

/// The subject countersigns this proof inside the origin/request transcript.
pub(crate) fn create(
    store: Option<&Arc<Persistence>>,
    peer: Option<&str>,
    subject: &str,
) -> Result<Option<String>, DeletionError> {
    let Some(identity) = local_identity(store, peer)? else {
        return Ok(None);
    };
    let Some(certificate) = identity.account_certificate().map_err(identity_error)? else {
        return Ok(None);
    };
    let mut proof = AccountProof {
        certificate,
        subject: subject.into(),
        signature: String::new(),
    };
    proof.signature = hex::encode(
        identity
            .key()
            .sign(&proof.input().map_err(DeletionError::Internal)?)
            .to_bytes(),
    );
    serde_json::to_string(&proof)
        .map(Some)
        .map_err(|e| DeletionError::Internal(e.to_string()))
}

/// Own Moss keys are known locally even before post-link certificates arrive.
pub(crate) fn moss_accounts(
    store: Option<&Arc<Persistence>>,
    peer: Option<&str>,
) -> Result<std::collections::BTreeMap<String, String>, DeletionError> {
    let Some(identity) = local_identity(store, peer)? else {
        return Ok(Default::default());
    };
    let roster = identity.roster();
    let user = roster.user_id();
    let devices = roster.devices().map_err(identity_error)?;
    let removed = roster.removal_targets().map_err(identity_error)?;
    Ok(devices
        .into_iter()
        .chain(removed)
        .map(|device| (device.moss_peer_id, user.clone()))
        .collect())
}

fn local_identity(
    store: Option<&Arc<Persistence>>,
    peer: Option<&str>,
) -> Result<Option<DeviceIdentity>, DeletionError> {
    let (Some(store), Some(peer)) = (store, peer) else {
        return Ok(None);
    };
    let identity = DeviceIdentity::open(store.clone(), peer).map_err(identity_error)?;
    if identity.revoked().map_err(identity_error)? {
        return Err(DeletionError::Revoked);
    }
    Ok(Some(identity))
}

fn identity_error(error: crate::device_link::types::DeviceLinkError) -> DeletionError {
    use crate::device_link::types::DeviceLinkErrorKind;
    match error.kind {
        DeviceLinkErrorKind::Storage | DeviceLinkErrorKind::InvalidRoster => {
            DeletionError::Persistence(error.to_string())
        }
        _ => DeletionError::Internal(error.to_string()),
    }
}

pub(crate) fn verify(proof: &str, subject: &str) -> Result<String, String> {
    if proof.len() > 16000 {
        return Err("account proof too large".into());
    }
    let proof: AccountProof = serde_json::from_str(proof).map_err(|e| e.to_string())?;
    proof.verify(subject)?;
    Ok(proof.certificate.root)
}

pub(crate) fn same_account(
    actor: &str,
    actor_proof: Option<&str>,
    author: &str,
    author_proof: Option<&str>,
) -> bool {
    let (Some(actor_proof), Some(author_proof)) = (actor_proof, author_proof) else {
        return false;
    };
    let verified = || -> Result<bool, String> {
        let actor_proof: AccountProof =
            serde_json::from_str(actor_proof).map_err(|e| e.to_string())?;
        let author_proof: AccountProof =
            serde_json::from_str(author_proof).map_err(|e| e.to_string())?;
        actor_proof.verify(actor)?;
        author_proof.verify(author)?;
        Ok(actor_proof.certificate.root == author_proof.certificate.root)
    };
    verified().unwrap_or(false)
}
