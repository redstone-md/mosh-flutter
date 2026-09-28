use std::sync::Arc;

use ed25519_dalek::SigningKey;
use rand::rngs::OsRng;
use serde::{Deserialize, Serialize};

use super::qr::PairingQr;
use super::roster::{invalid, DeviceRoster};
use super::types::{DeviceDescriptor, DeviceLinkError, DeviceLinkErrorKind, Result};
use crate::persistence::Persistence;

#[derive(Clone, Serialize, Deserialize)]
pub(crate) struct LinkDelivery {
    pub qr: PairingQr,
    pub packet: Vec<u8>,
    pub roster_hash: String,
}

#[derive(Clone, Serialize, Deserialize)]
pub(crate) struct LinkReceipt {
    pub qr: PairingQr,
    pub trusted: DeviceDescriptor,
    pub roster_hash: String,
    pub packet: Vec<u8>,
}

#[derive(Clone, Serialize, Deserialize)]
pub(crate) struct PendingJoin {
    pub qr: PairingQr,
    pub trusted: DeviceDescriptor,
    pub base: DeviceRoster,
}

#[derive(Clone, Serialize, Deserialize)]
pub(crate) struct LocalIdentity {
    pub seed: [u8; 32],
    pub device: DeviceDescriptor,
    pub roster: DeviceRoster,
    #[serde(default)]
    pub delivery: Option<LinkDelivery>,
    #[serde(default)]
    pub receipt: Option<LinkReceipt>,
    #[serde(default)]
    pub pending: Option<PendingJoin>,
}

pub struct DeviceIdentity {
    store: Arc<Persistence>,
    pub(crate) record: LocalIdentity,
}

pub(crate) fn storage_error(_: impl std::fmt::Display) -> DeviceLinkError {
    DeviceLinkError::new(DeviceLinkErrorKind::Storage)
}

impl DeviceIdentity {
    pub fn open(store: Arc<Persistence>, peer_id: &str) -> Result<Self> {
        let record = match store.get_device_link().map_err(storage_error)? {
            Some(bytes) => {
                serde_json::from_slice::<LocalIdentity>(&bytes).map_err(storage_error)?
            }
            None => {
                let key = SigningKey::generate(&mut OsRng);
                let device = DeviceDescriptor::new(&key, peer_id);
                let roster = DeviceRoster::genesis(device.clone(), &key)?;
                LocalIdentity {
                    seed: key.to_bytes(),
                    device,
                    roster,
                    delivery: None,
                    receipt: None,
                    pending: None,
                }
            }
        };
        let identity = Self { store, record };
        identity.validate(peer_id)?;
        identity.save(&identity.record)?;
        Ok(identity)
    }

    fn validate(&self, peer_id: &str) -> Result<()> {
        let device = self.device();
        if device.moss_peer_id != peer_id
            || hex::encode(self.key().verifying_key().as_bytes()) != device.signing_public_key
            || !self.roster().devices()?.contains(device)
        {
            return Err(invalid());
        }
        if let Some(pending) = &self.record.pending {
            let devices = pending.base.devices()?;
            if pending.qr.device != *device
                || !self.can_join()?
                || self.record.delivery.is_some()
                || !devices.contains(&pending.trusted)
                || devices.iter().any(|d| {
                    d.device_id == device.device_id || d.moss_peer_id == device.moss_peer_id
                })
            {
                return Err(invalid());
            }
        }
        Ok(())
    }

    pub fn device(&self) -> &DeviceDescriptor {
        &self.record.device
    }
    pub fn roster(&self) -> &DeviceRoster {
        &self.record.roster
    }
    pub(crate) fn key(&self) -> SigningKey {
        SigningKey::from_bytes(&self.record.seed)
    }

    pub(crate) fn can_join(&self) -> Result<bool> {
        Ok(self.roster().devices()?.len() == 1
            && self
                .store
                .list_sessions()
                .map_err(storage_error)?
                .is_empty()
            && self.store.list_groups().map_err(storage_error)?.is_empty()
            && self
                .store
                .list_channels()
                .map_err(storage_error)?
                .is_empty()
            && self
                .store
                .list_org_records()
                .map_err(storage_error)?
                .is_empty())
    }

    pub(crate) fn update(&mut self, record: LocalIdentity) -> Result<()> {
        if !record.roster.devices()?.contains(&record.device) {
            return Err(invalid());
        }
        self.save(&record)?;
        self.record = record;
        Ok(())
    }

    fn save(&self, record: &LocalIdentity) -> Result<()> {
        let bytes = serde_json::to_vec(record).map_err(storage_error)?;
        self.store.put_device_link(&bytes).map_err(storage_error)
    }
}
