use super::DeletionError;
use crate::device_link::{account_certificate::AccountCertificate, identity::DeviceIdentity};
use crate::persistence::Persistence;
use ed25519_dalek::Signer;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::sync::Arc;

#[derive(Default)]
pub(crate) struct OwnAccounts {
    pub accounts: BTreeMap<String, String>,
    pub revoked: BTreeSet<String>,
}

impl OwnAccounts {
    pub fn same_account(
        &self,
        left: &str,
        left_proof: Option<&str>,
        right: &str,
        right_proof: Option<&str>,
    ) -> bool {
        self.account(left, left_proof)
            .is_some_and(|user| self.account(right, right_proof) == Some(user))
    }

    fn account(&self, key: &str, proof: Option<&str>) -> Option<&String> {
        self.accounts.get(key).or_else(|| {
            let signer = verified_proof(proof?, key)
                .ok()?
                .certificate
                .subject()
                .to_owned();
            self.accounts.get(&signer)
        })
    }

    pub fn for_mls(self, crypto: &crate::mls_crypto::MlsSessionCrypto) -> Self {
        let mut mapped = self;
        for signer in crypto.member_signers() {
            let identity = hex::decode(&signer)
                .ok()
                .and_then(|key| crypto.member_identity_for_signer(&key));
            let Some(identity) = identity else { continue };
            let Some(user) = mapped.accounts.get(&identity).cloned() else {
                continue;
            };
            mapped.accounts.insert(signer.clone(), user);
            if mapped.revoked.contains(&identity) {
                mapped.revoked.insert(signer);
            }
        }
        mapped
    }
}

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
) -> Result<OwnAccounts, DeletionError> {
    let Some(identity) = local_identity(store, peer)? else {
        return Ok(Default::default());
    };
    let roster = identity.roster();
    let user = roster.user_id();
    let devices = roster.devices().map_err(identity_error)?;
    let removed = roster.removal_targets().map_err(identity_error)?;
    Ok(OwnAccounts {
        revoked: removed
            .iter()
            .flat_map(|d| [d.moss_peer_id.clone(), d.signing_public_key.clone()])
            .collect(),
        accounts: devices
            .into_iter()
            .chain(removed)
            .flat_map(|device| {
                [
                    (device.moss_peer_id, user.clone()),
                    (device.signing_public_key, user.clone()),
                ]
            })
            .collect(),
    })
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

#[cfg(test)]
pub(crate) fn test_proof(key: &ed25519_dalek::SigningKey) -> String {
    signed_test_proof(AccountCertificate::root(key), key)
}

#[cfg(test)]
pub(crate) fn test_linked_proof(
    root: &ed25519_dalek::SigningKey,
    linked: &ed25519_dalek::SigningKey,
) -> String {
    signed_test_proof(
        AccountCertificate::root(root)
            .issue(&hex::encode(linked.verifying_key().as_bytes()), root)
            .unwrap(),
        linked,
    )
}

#[cfg(test)]
fn signed_test_proof(certificate: AccountCertificate, key: &ed25519_dalek::SigningKey) -> String {
    let mut proof = AccountProof {
        certificate,
        subject: hex::encode(key.verifying_key().as_bytes()),
        signature: String::new(),
    };
    proof.signature = hex::encode(key.sign(&proof.input().unwrap()).to_bytes());
    serde_json::to_string(&proof).unwrap()
}

pub(crate) fn verify(proof: &str, subject: &str) -> Result<String, String> {
    Ok(verified_proof(proof, subject)?.certificate.root)
}

fn verified_proof(proof: &str, subject: &str) -> Result<AccountProof, String> {
    if proof.len() > 16000 {
        return Err("account proof too large".into());
    }
    let proof: AccountProof = serde_json::from_str(proof).map_err(|e| e.to_string())?;
    proof.verify(subject)?;
    Ok(proof)
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
        let actor_proof = verified_proof(actor_proof, actor)?;
        let author_proof = verified_proof(author_proof, author)?;
        Ok(actor_proof.certificate.root == author_proof.certificate.root)
    };
    verified().unwrap_or(false)
}
