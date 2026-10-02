use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use rand::{rngs::OsRng, RngCore};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use super::types::{DeviceDescriptor, DeviceLinkError, DeviceLinkErrorKind, Result};

const QR_PREFIX: &str = "mosh://device-link/";
const QR_VERSION: u32 = 2;
pub(crate) const QR_LIFETIME_SECONDS: u64 = 300;
const MAX_QR_BYTES: usize = 2048;
const CODE_CONTEXT: &[u8] = b"mosh-device-code-v2\0";
const LEGACY_CODE_CONTEXT: &[u8] = b"mosh-device-code-v1\0";
const CODE_HEX_CHARS: usize = 12;

#[derive(Clone, Serialize, Deserialize)]
pub(crate) struct PairingQr {
    version: u32,
    pub id: String,
    pub expires_at: u64,
    pub device: DeviceDescriptor,
    pub secret: [u8; 32],
}

impl PairingQr {
    pub fn new(device: DeviceDescriptor, now: u64) -> Self {
        let mut secret = [0; 32];
        let mut id = [0; 16];
        OsRng.fill_bytes(&mut secret);
        OsRng.fill_bytes(&mut id);
        Self {
            version: QR_VERSION,
            id: hex::encode(id),
            expires_at: now + QR_LIFETIME_SECONDS,
            device,
            secret,
        }
    }

    pub fn uri(&self) -> Result<String> {
        let bytes = serde_json::to_vec(self).map_err(|_| Self::invalid())?;
        Ok(format!("{QR_PREFIX}{}", URL_SAFE_NO_PAD.encode(bytes)))
    }

    pub fn parse(uri: &str, now: u64) -> Result<Self> {
        if uri.len() > MAX_QR_BYTES {
            return Err(Self::invalid());
        }
        let data = uri
            .trim()
            .strip_prefix(QR_PREFIX)
            .ok_or_else(Self::invalid)?;
        let bytes = URL_SAFE_NO_PAD.decode(data).map_err(|_| Self::invalid())?;
        let qr: Self = serde_json::from_slice(&bytes).map_err(|_| Self::invalid())?;
        qr.validate(now)?;
        Ok(qr)
    }

    fn validate(&self, now: u64) -> Result<()> {
        if !self.is_current() {
            return Err(Self::invalid());
        }
        self.validate_stored()?;
        if self.expires_at <= now || self.expires_at > now + QR_LIFETIME_SECONDS {
            return Err(DeviceLinkError::new(DeviceLinkErrorKind::Expired));
        }
        Ok(())
    }

    pub fn is_current(&self) -> bool {
        self.version == QR_VERSION
    }

    /// Legacy committed deliveries still use their original authenticated QR.
    pub fn validate_stored(&self) -> Result<()> {
        if !matches!(self.version, 1 | QR_VERSION)
            || self.id.len() != 32
            || hex::decode(&self.id).is_err()
            || self.secret == [0; 32]
        {
            return Err(Self::invalid());
        }
        self.device.validate().map_err(|_| Self::invalid())?;
        Ok(())
    }

    pub fn digest(&self) -> Result<Vec<u8>> {
        Ok(Sha256::digest(serde_json::to_vec(self).map_err(|_| Self::invalid())?).to_vec())
    }

    pub fn code(
        &self,
        offer_hash: &str,
        trusted: &DeviceDescriptor,
        joining: &DeviceDescriptor,
    ) -> Result<String> {
        let mut hash = Sha256::new();
        hash.update(if self.is_current() {
            CODE_CONTEXT
        } else {
            LEGACY_CODE_CONTEXT
        });
        hash.update(self.digest()?);
        hash.update(offer_hash.as_bytes());
        hash.update(trusted.signing_public_key.as_bytes());
        if self.is_current() {
            hash.update(serde_json::to_vec(joining).map_err(|_| Self::invalid())?);
        }
        Ok(hex::encode(hash.finalize())[..CODE_HEX_CHARS].to_uppercase())
    }

    fn invalid() -> DeviceLinkError {
        DeviceLinkError::new(DeviceLinkErrorKind::InvalidQr)
    }
}
