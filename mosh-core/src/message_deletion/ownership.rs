use crate::device_link::{identity::DeviceIdentity, roster::DeviceRoster};
use crate::persistence::Persistence;
use ed25519_dalek::Signer;
use serde::{Deserialize, Serialize};
use std::sync::Arc;

#[derive(Serialize, Deserialize)]
struct AccountProof {
    roster: DeviceRoster,
    device: String,
    subject: String,
    signature: String,
}

impl AccountProof {
    fn input(&self) -> Result<Vec<u8>, String> {
        let mut bytes = b"mosh-message-account-v1\0".to_vec();
        bytes.extend(
            serde_json::to_vec(&(
                &self.device,
                &self.subject,
                self.roster.digest().map_err(|e| e.to_string())?,
            ))
            .map_err(|e| e.to_string())?,
        );
        Ok(bytes)
    }
    fn verify(&self, subject: &str) -> Result<(), String> {
        if self.subject != subject {
            return Err("account subject mismatch".into());
        }
        let device = self
            .roster
            .devices()
            .map_err(|e| e.to_string())?
            .into_iter()
            .find(|d| d.device_id == self.device)
            .ok_or("account device removed")?;
        super::origin::verify_signature(&device.signing_public_key, &self.signature, &self.input()?)
    }
}

/// The subject countersigns this proof inside the origin/request transcript.
pub(crate) fn create(
    store: Option<&Arc<Persistence>>,
    peer: Option<&str>,
    subject: &str,
) -> Result<Option<String>, String> {
    let (Some(store), Some(peer)) = (store, peer) else {
        return Ok(None);
    };
    let identity = DeviceIdentity::open(store.clone(), peer).map_err(|e| e.to_string())?;
    if identity.revoked().map_err(|e| e.to_string())? {
        return Err("device removed from account".into());
    }
    let mut proof = AccountProof {
        roster: identity.roster().clone(),
        device: identity.device().device_id.clone(),
        subject: subject.into(),
        signature: String::new(),
    };
    proof.signature = hex::encode(identity.key().sign(&proof.input()?).to_bytes());
    serde_json::to_string(&proof)
        .map(Some)
        .map_err(|e| e.to_string())
}

pub(crate) fn verify(proof: &str, subject: &str) -> Result<String, String> {
    if proof.len() > 16000 {
        return Err("account proof too large".into());
    }
    let proof: AccountProof = serde_json::from_str(proof).map_err(|e| e.to_string())?;
    proof.verify(subject)?;
    Ok(proof.roster.user_id())
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
        if actor_proof.roster.user_id() != author_proof.roster.user_id() {
            return Ok(false);
        }
        let newest = if actor_proof
            .roster
            .extends(&author_proof.roster)
            .map_err(|e| e.to_string())?
        {
            &actor_proof.roster
        } else if author_proof
            .roster
            .extends(&actor_proof.roster)
            .map_err(|e| e.to_string())?
        {
            &author_proof.roster
        } else {
            return Ok(false);
        };
        Ok(newest
            .devices()
            .map_err(|e| e.to_string())?
            .iter()
            .any(|d| d.device_id == actor_proof.device))
    };
    verified().unwrap_or(false)
}
