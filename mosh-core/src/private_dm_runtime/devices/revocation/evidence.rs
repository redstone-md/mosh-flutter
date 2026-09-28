use super::*;
use ed25519_dalek::Signer;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

const CONTEXT: &[u8] = b"mosh-dm-removal-evidence-v1\0";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(in crate::private_dm_runtime::devices) struct RemovalRecord {
    pub session_id: String,
    pub author: String,
    pub target: String,
    pub roster: DeviceRoster,
    pub commit: Vec<u8>,
    pub group_id: Vec<u8>,
    pub epoch: u64,
    signature: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(in crate::private_dm_runtime::devices) struct RemovalJournal {
    pub evidence: RemovalRecord,
    pub waiting: Vec<String>,
}

impl RemovalRecord {
    pub(in crate::private_dm_runtime::devices) fn create(
        identity: &DeviceIdentity,
        session: &str,
        target: String,
        roster: DeviceRoster,
        crypto: &crate::mls_crypto::MlsSessionCrypto,
        commit: Vec<u8>,
    ) -> Result<Self> {
        let mut record = Self {
            session_id: session.into(),
            author: identity.device().device_id.clone(),
            target,
            roster,
            commit,
            group_id: crypto.group_id_bytes().ok_or_else(invalid)?,
            epoch: crypto.epoch().ok_or_else(invalid)?,
            signature: String::new(),
        };
        record.signature = hex::encode(identity.key().sign(&record.bytes()?).to_bytes());
        Ok(record)
    }

    fn bytes(&self) -> Result<Vec<u8>> {
        let mut bytes = CONTEXT.to_vec();
        bytes.extend(
            serde_json::to_vec(&(
                &self.session_id,
                &self.author,
                &self.target,
                &self.roster,
                &self.commit,
                &self.group_id,
                self.epoch,
            ))
            .map_err(|_| invalid())?,
        );
        Ok(bytes)
    }

    pub(super) fn digest(&self) -> Result<String> {
        Ok(hex::encode(Sha256::digest(
            serde_json::to_vec(self).map_err(|_| invalid())?,
        )))
    }

    pub(super) fn verify(&self, session: &PrivateDmSession) -> Result<String> {
        let author = self.verify_author(session)?;
        let membership = session.membership.as_ref().ok_or_else(invalid)?;
        let target = membership
            .topology
            .clients
            .iter()
            .find(|c| c.device_id == self.target)
            .ok_or_else(invalid)?;
        let base = membership
            .topology
            .roster(&author.roster.user_id())
            .ok_or_else(invalid)?;
        if target.roster.user_id() != author.roster.user_id() {
            return Err(invalid());
        }
        self.roster
            .verifies_removal(base, &self.target, &self.author)
            .map_err(|_| invalid())?;
        Ok(author.mls_signer)
    }

    pub(super) fn verify_author(&self, session: &PrivateDmSession) -> Result<IdentityClaim> {
        let membership = session.membership.as_ref().ok_or_else(invalid)?;
        let author = membership
            .topology
            .clients
            .iter()
            .find(|c| c.device_id == self.author)
            .ok_or_else(invalid)?;
        let base = membership
            .topology
            .roster(&author.roster.user_id())
            .ok_or_else(invalid)?;
        if self.session_id != session.session_id
            || self.group_id != session.crypto.group_id_bytes().ok_or_else(invalid)?
            || !base
                .devices()
                .map_err(|_| invalid())?
                .contains(&author.device()?)
        {
            return Err(invalid());
        }
        self.roster
            .verifies_removal_extension(base, &self.target, &self.author)
            .map_err(|_| invalid())?;
        super::super::proof::verify(
            &author.device()?.signing_public_key,
            &self.signature,
            &self.bytes()?,
        )?;
        Ok(author.clone())
    }
}

impl DeviceMembership {
    pub(super) fn retain_removal(&mut self, evidence: RemovalRecord, local: &str) -> Result<()> {
        if self.epoch_records.iter().any(|r| r.epoch == evidence.epoch) {
            return Err(invalid());
        }
        if let Some(existing) = self
            .removals
            .iter()
            .find(|r| r.evidence.epoch == evidence.epoch)
        {
            return if existing.evidence.digest()? == evidence.digest()? {
                Ok(())
            } else {
                Err(invalid())
            };
        }
        let waiting = self
            .topology
            .clients
            .iter()
            .filter(|c| c.device_id != local && c.device_id != evidence.author)
            .map(|c| Ok(c.device()?.moss_peer_id))
            .collect::<Result<Vec<_>>>()?;
        self.removals.push(RemovalJournal { evidence, waiting });
        Ok(())
    }
}
