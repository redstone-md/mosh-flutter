use super::PlusFrame;
use crate::{
    conversation::{decode, encode},
    mls_crypto::MlsSessionCrypto,
};
use aes_gcm::{
    aead::{Aead, KeyInit, Payload},
    Aes256Gcm, Nonce,
};
use rand::RngCore;
use serde::{Deserialize, Serialize};

#[derive(Default)]
pub(crate) struct PlusSchedule {
    last_attempt: u64,
}

impl PlusSchedule {
    pub(crate) fn due(&mut self, now: u64) -> bool {
        if now.saturating_sub(self.last_attempt) < 5000 {
            return false;
        }
        self.last_attempt = now;
        true
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SealedPlusFrame {
    pub epoch: u64,
    pub ciphertext_b64: String,
}

fn cipher(crypto: &MlsSessionCrypto, context: &str) -> Result<Aes256Gcm, String> {
    let key = crypto
        .metadata_key("mosh-plus-metadata-v1", context.as_bytes())
        .map_err(|e| e.to_string())?;
    Aes256Gcm::new_from_slice(&key).map_err(|_| "invalid PLUS metadata key".into())
}

pub(crate) fn seal_mls(
    crypto: &MlsSessionCrypto,
    context: &str,
    frame: &PlusFrame,
) -> Result<SealedPlusFrame, String> {
    let bytes = serde_json::to_vec(frame).map_err(|_| "PLUS encoding failed")?;
    if bytes.len() > 22_000 {
        return Err("PLUS frame exceeds network limit".into());
    }
    let mut nonce = [0; 12];
    rand::rngs::OsRng.fill_bytes(&mut nonce);
    let encrypted = cipher(crypto, context)?
        .encrypt(
            Nonce::from_slice(&nonce),
            Payload {
                msg: &bytes,
                aad: context.as_bytes(),
            },
        )
        .map_err(|_| "PLUS encryption failed")?;
    let mut payload = nonce.to_vec();
    payload.extend(encrypted);
    Ok(SealedPlusFrame {
        epoch: crypto.epoch().ok_or("MLS not ready")?,
        ciphertext_b64: encode(&payload),
    })
}

pub(crate) fn open_mls(
    crypto: &MlsSessionCrypto,
    context: &str,
    frame: &SealedPlusFrame,
) -> Result<PlusFrame, String> {
    if crypto.epoch() != Some(frame.epoch) || frame.ciphertext_b64.len() > 30_000 {
        return Err("PLUS epoch/size mismatch".into());
    }
    let bytes = decode(&frame.ciphertext_b64).map_err(|_| "invalid PLUS encoding")?;
    if bytes.len() < 28 {
        return Err("truncated PLUS frame".into());
    }
    let opened = cipher(crypto, context)?
        .decrypt(
            Nonce::from_slice(&bytes[..12]),
            Payload {
                msg: &bytes[12..],
                aad: context.as_bytes(),
            },
        )
        .map_err(|_| "invalid PLUS ciphertext")?;
    serde_json::from_slice(&opened).map_err(|_| "invalid PLUS payload".into())
}
