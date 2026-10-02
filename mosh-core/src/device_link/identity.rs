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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub joining: Option<DeviceDescriptor>,
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub joining: Option<DeviceDescriptor>,
    pub trusted: DeviceDescriptor,
    pub base: DeviceRoster,
}

impl LinkDelivery {
    pub fn joining_device(&self) -> &DeviceDescriptor {
        self.joining.as_ref().unwrap_or(&self.qr.device)
    }
}

impl PendingJoin {
    pub fn joining_device(&self) -> &DeviceDescriptor {
        self.joining.as_ref().unwrap_or(&self.qr.device)
    }
}

#[derive(Clone, Serialize, Deserialize)]
struct ConsumedRequest {
    id: String,
    expires_at: u64,
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
    #[serde(default)]
    consumed: Vec<ConsumedRequest>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub roster_delivery: Vec<DeviceDescriptor>,
}

impl LocalIdentity {
    pub(crate) fn consume(&mut self, qr: &PairingQr, now: u64) {
        self.consumed.retain(|request| request.expires_at > now);
        if qr.expires_at > now && !self.consumed(qr, now) {
            self.consumed.push(ConsumedRequest {
                id: qr.id.clone(),
                expires_at: qr.expires_at,
            });
        }
    }

    pub(crate) fn consumed(&self, qr: &PairingQr, now: u64) -> bool {
        self.consumed
            .iter()
            .any(|request| request.id == qr.id && request.expires_at > now)
    }
}

pub struct DeviceIdentity {
    store: Arc<Persistence>,
    persisted: Vec<u8>,
    pub(crate) record: LocalIdentity,
}

pub(crate) fn storage_error(_: impl std::fmt::Display) -> DeviceLinkError {
    DeviceLinkError::new(DeviceLinkErrorKind::Storage)
}

impl DeviceIdentity {
    pub fn open(store: Arc<Persistence>, peer_id: &str) -> Result<Self> {
        let persisted = match store.get_device_link().map_err(storage_error)? {
            Some(bytes) => bytes,
            None => {
                let key = SigningKey::generate(&mut OsRng);
                let device = DeviceDescriptor::new(&key, peer_id);
                let roster = DeviceRoster::genesis(device.clone(), &key)?;
                let candidate = LocalIdentity {
                    seed: key.to_bytes(),
                    device,
                    roster,
                    delivery: None,
                    receipt: None,
                    pending: None,
                    consumed: Vec::new(),
                    roster_delivery: Vec::new(),
                };
                let bytes = serde_json::to_vec(&candidate).map_err(storage_error)?;
                store
                    .initialize_device_link(&bytes)
                    .map_err(storage_error)?
            }
        };
        let record = serde_json::from_slice(&persisted).map_err(storage_error)?;
        let identity = Self {
            store,
            persisted,
            record,
        };
        identity.validate(peer_id)?;
        Ok(identity)
    }

    fn validate(&self, peer_id: &str) -> Result<()> {
        let device = self.device();
        if device.moss_peer_id != peer_id
            || hex::encode(self.key().verifying_key().as_bytes()) != device.signing_public_key
            || self.roster().known_device(&device.device_id)?.as_ref() != Some(device)
        {
            return Err(invalid());
        }
        if let Some(pending) = &self.record.pending {
            let devices = pending.base.devices()?;
            pending.qr.validate_stored()?;
            if pending.joining_device() != device
                || (pending.qr.is_current()
                    && (pending.joining.is_none() || pending.qr.device != pending.trusted))
                || (self.revoked()? && !pending.base.extends(self.roster())?)
                || self.record.delivery.is_some()
                || !devices.contains(&pending.trusted)
                || devices.iter().any(|d| {
                    d.device_id == device.device_id || d.moss_peer_id == device.moss_peer_id
                })
            {
                return Err(invalid());
            }
        }
        if let Some(delivery) = &self.record.delivery {
            delivery.qr.validate_stored()?;
            if delivery.qr.is_current()
                && (delivery.joining.is_none() || delivery.qr.device != *device)
            {
                return Err(invalid());
            }
            delivery.joining_device().validate()?;
        }
        if let Some(receipt) = &self.record.receipt {
            receipt.qr.validate_stored()?;
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
        if self.revoked()? {
            return Ok(true);
        }
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
        if record
            .roster
            .known_device(&record.device.device_id)?
            .as_ref()
            != Some(&record.device)
        {
            return Err(invalid());
        }
        let bytes = serde_json::to_vec(&record).map_err(storage_error)?;
        if !self
            .store
            .replace_device_link(&self.persisted, &bytes)
            .map_err(storage_error)?
        {
            return Err(DeviceLinkError::new(DeviceLinkErrorKind::Busy));
        }
        self.persisted = bytes;
        self.record = record;
        Ok(())
    }

    pub(crate) fn reload(&mut self) -> Result<()> {
        let next = Self::open(self.store.clone(), &self.device().moss_peer_id)?;
        self.record = next.record;
        self.persisted = next.persisted;
        Ok(())
    }

    pub(crate) fn revoked(&self) -> Result<bool> {
        Ok(!self.roster().devices()?.contains(self.device()))
    }

    pub(crate) fn revocations(&self) -> Result<Vec<super::types::DeviceRevocationStatus>> {
        let records = self
            .store
            .list_sessions()
            .map_err(storage_error)?
            .iter()
            .map(|bytes| {
                serde_json::from_slice::<crate::private_dm_runtime::contracts::PersistedSession>(
                    bytes,
                )
                .map_err(storage_error)
            })
            .collect::<Result<Vec<_>>>()?;
        let active = self.roster().devices()?;
        Ok(self
            .roster()
            .removal_targets()?
            .into_iter()
            .filter_map(|device| {
                let pending = records.iter().any(|record| {
                    record
                        .membership
                        .as_ref()
                        .is_some_and(|m| m.removal_pending(&device.device_id, self.roster()))
                });
                (pending || !active.contains(&device)).then_some(
                    super::types::DeviceRevocationStatus {
                        device,
                        state: if pending {
                            super::types::DeviceRevocationState::Pending
                        } else {
                            super::types::DeviceRevocationState::Applied
                        },
                    },
                )
            })
            .collect())
    }

    pub(crate) fn adopt_roster(&mut self, roster: DeviceRoster) -> Result<()> {
        if !roster.extends(self.roster())? {
            return Err(invalid());
        }
        let mut record = self.record.clone();
        record.roster = roster;
        if !record.roster.devices()?.contains(&record.device) {
            record.delivery = None;
            record.receipt = None;
            record.pending = None;
            record.roster_delivery.clear();
        }
        self.update(record)
    }
}
