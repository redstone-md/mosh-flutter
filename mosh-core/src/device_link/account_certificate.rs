//! Public account delegation contains keys and signatures, never the private roster.
use ed25519_dalek::{Signer, SigningKey};
use serde::{Deserialize, Serialize};

use super::{
    roster::{invalid, public_key},
    types::Result,
};

const CONTEXT: &[u8] = b"mosh-account-delegation-v1\0";
const MAX_DELEGATIONS: usize = 32;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct AccountCertificate {
    pub root: String,
    delegations: Vec<Delegation>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct Delegation {
    key: String,
    signature: String,
}

impl AccountCertificate {
    pub fn root(key: &SigningKey) -> Self {
        Self {
            root: hex::encode(key.verifying_key().as_bytes()),
            delegations: Vec::new(),
        }
    }

    pub fn subject(&self) -> &str {
        self.delegations.last().map_or(&self.root, |d| &d.key)
    }

    pub fn keys(&self) -> impl Iterator<Item = &str> {
        std::iter::once(self.root.as_str()).chain(self.delegations.iter().map(|d| d.key.as_str()))
    }

    pub fn issuer(&self) -> Option<&str> {
        self.delegations.last().map(|_| {
            self.delegations
                .iter()
                .rev()
                .nth(1)
                .map_or(self.root.as_str(), |d| d.key.as_str())
        })
    }

    fn input(&self, prefix: usize, key: &str) -> Result<Vec<u8>> {
        let mut bytes = CONTEXT.to_vec();
        bytes.extend(
            serde_json::to_vec(&(&self.root, &self.delegations[..prefix], key))
                .map_err(|_| invalid())?,
        );
        Ok(bytes)
    }

    pub fn verify(&self) -> Result<()> {
        if self.delegations.len() > MAX_DELEGATIONS {
            return Err(invalid());
        }
        let mut signer = public_key(&self.root)?;
        let mut known = std::collections::BTreeSet::from([self.root.as_str()]);
        for (index, delegation) in self.delegations.iter().enumerate() {
            let next = public_key(&delegation.key)?;
            if !known.insert(&delegation.key) {
                return Err(invalid());
            }
            let signature = hex::decode(&delegation.signature).map_err(|_| invalid())?;
            signer
                .verify_strict(
                    &self.input(index, &delegation.key)?,
                    &ed25519_dalek::Signature::from_slice(&signature).map_err(|_| invalid())?,
                )
                .map_err(|_| invalid())?;
            signer = next;
        }
        Ok(())
    }

    pub fn issue(&self, subject: &str, signer: &SigningKey) -> Result<Self> {
        self.verify()?;
        if self.subject() != hex::encode(signer.verifying_key().as_bytes()) {
            return Err(invalid());
        }
        let mut next = self.clone();
        let signature = hex::encode(
            signer
                .sign(&self.input(self.delegations.len(), subject)?)
                .to_bytes(),
        );
        next.delegations.push(Delegation {
            key: subject.into(),
            signature,
        });
        next.verify()?;
        Ok(next)
    }
}
