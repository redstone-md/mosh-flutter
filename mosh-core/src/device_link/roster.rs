use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use super::types::{DeviceDescriptor, DeviceLinkError, DeviceLinkErrorKind, Result};

const ROSTER_CONTEXT: &[u8] = b"mosh-device-roster-v1\0";
const DEVICE_CONTEXT: &[u8] = b"mosh-device-id-v1\0";
const ROSTER_VERSION: u32 = 1;
pub(crate) const DEFAULT_DEVICE_NAME: &str = "Desktop";
pub(crate) const MAX_NAME_CHARS: usize = 64;

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Authorization {
    version: u32,
    parent: Option<String>,
    signer: String,
    device: DeviceDescriptor,
    signature: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceRoster {
    entries: Vec<Authorization>,
}

pub(crate) fn invalid() -> DeviceLinkError {
    DeviceLinkError::new(DeviceLinkErrorKind::InvalidRoster)
}

pub(crate) fn public_key(hex_key: &str) -> Result<VerifyingKey> {
    let bytes: [u8; 32] = hex::decode(hex_key)
        .map_err(|_| invalid())?
        .try_into()
        .map_err(|_| invalid())?;
    let key = VerifyingKey::from_bytes(&bytes).map_err(|_| invalid())?;
    if key.is_weak() || hex::encode(bytes) != hex_key {
        return Err(invalid());
    }
    Ok(key)
}

pub(crate) fn device_id(key: &VerifyingKey) -> String {
    let mut hash = Sha256::new();
    hash.update(DEVICE_CONTEXT);
    hash.update(key.as_bytes());
    hex::encode(hash.finalize())
}

impl DeviceDescriptor {
    pub(crate) fn new(key: &SigningKey, peer: &str) -> Self {
        Self {
            device_id: device_id(&key.verifying_key()),
            signing_public_key: hex::encode(key.verifying_key().as_bytes()),
            moss_peer_id: peer.into(),
            name: DEFAULT_DEVICE_NAME.into(),
        }
    }

    pub(crate) fn validate(&self) -> Result<()> {
        let key = public_key(&self.signing_public_key)?;
        if self.device_id != device_id(&key)
            || self.name.is_empty()
            || self.name.chars().count() > MAX_NAME_CHARS
            || self.name.chars().any(char::is_control)
        {
            return Err(invalid());
        }
        public_key(&self.moss_peer_id)?;
        Ok(())
    }
}

impl Authorization {
    fn bytes(&self) -> Result<Vec<u8>> {
        let content = (&self.version, &self.parent, &self.signer, &self.device);
        let mut bytes = ROSTER_CONTEXT.to_vec();
        bytes.extend(serde_json::to_vec(&content).map_err(|_| invalid())?);
        Ok(bytes)
    }

    fn signed(
        parent: Option<String>,
        signer: String,
        device: DeviceDescriptor,
        key: &SigningKey,
    ) -> Result<Self> {
        let mut entry = Self {
            version: ROSTER_VERSION,
            parent,
            signer,
            device,
            signature: String::new(),
        };
        entry.signature = hex::encode(key.sign(&entry.bytes()?).to_bytes());
        Ok(entry)
    }
}

impl DeviceRoster {
    pub(crate) fn extends(&self, base: &Self) -> Result<bool> {
        self.devices()?;
        if self.entries.len() < base.entries.len() {
            return Ok(false);
        }
        let prefix = Self {
            entries: self.entries[..base.entries.len()].to_vec(),
        };
        Ok(prefix.digest()? == base.digest()?)
    }

    pub(crate) fn genesis(device: DeviceDescriptor, key: &SigningKey) -> Result<Self> {
        let entry = Authorization::signed(None, device.device_id.clone(), device, key)?;
        let roster = Self {
            entries: vec![entry],
        };
        roster.devices()?;
        Ok(roster)
    }

    pub fn user_id(&self) -> String {
        self.entries
            .first()
            .map(|e| e.device.signing_public_key.clone())
            .unwrap_or_default()
    }

    pub fn digest(&self) -> Result<String> {
        let mut hash = Sha256::new();
        hash.update(ROSTER_CONTEXT);
        hash.update(serde_json::to_vec(self).map_err(|_| invalid())?);
        Ok(hex::encode(hash.finalize()))
    }

    pub fn devices(&self) -> Result<Vec<DeviceDescriptor>> {
        if self.entries.is_empty() {
            return Err(invalid());
        }
        let mut devices: Vec<DeviceDescriptor> = Vec::new();
        for (index, entry) in self.entries.iter().enumerate() {
            entry.device.validate()?;
            let key = self.authority(index, entry, &devices)?;
            let signature = hex::decode(&entry.signature).map_err(|_| invalid())?;
            let signature = Signature::from_slice(&signature).map_err(|_| invalid())?;
            key.verify_strict(&entry.bytes()?, &signature)
                .map_err(|_| invalid())?;
            if devices.iter().any(|d| {
                d.device_id == entry.device.device_id || d.moss_peer_id == entry.device.moss_peer_id
            }) {
                return Err(invalid());
            }
            devices.push(entry.device.clone());
        }
        Ok(devices)
    }

    fn authority(
        &self,
        index: usize,
        entry: &Authorization,
        devices: &[DeviceDescriptor],
    ) -> Result<VerifyingKey> {
        if entry.version != ROSTER_VERSION {
            return Err(invalid());
        }
        if index == 0 {
            if entry.parent.is_some() || entry.signer != entry.device.device_id {
                return Err(invalid());
            }
            return public_key(&entry.device.signing_public_key);
        }
        let parent = Self {
            entries: self.entries[..index].to_vec(),
        };
        if entry.parent.as_ref() != Some(&parent.digest()?) {
            return Err(invalid());
        }
        let signer = devices
            .iter()
            .find(|d| d.device_id == entry.signer)
            .ok_or_else(invalid)?;
        public_key(&signer.signing_public_key)
    }

    pub(crate) fn extend(&self, device: DeviceDescriptor, key: &SigningKey) -> Result<Self> {
        let signer = device_id(&key.verifying_key());
        let mut next = self.clone();
        next.entries.push(Authorization::signed(
            Some(self.digest()?),
            signer,
            device,
            key,
        )?);
        next.devices()?;
        Ok(next)
    }

    pub(crate) fn verifies_addition(
        &self,
        base: &Self,
        device: &DeviceDescriptor,
        signer: &str,
    ) -> Result<()> {
        self.devices()?;
        let Some(last) = self.entries.last() else {
            return Err(invalid());
        };
        let parent = Self {
            entries: self.entries[..self.entries.len() - 1].to_vec(),
        };
        if parent.digest()? != base.digest()? || &last.device != device || last.signer != signer {
            return Err(invalid());
        }
        Ok(())
    }
}
