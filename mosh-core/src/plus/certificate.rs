use base64::{engine::general_purpose::STANDARD, Engine};
use blind_rsa_signatures::pbrsa::PartiallyBlindPublicKeySha384PSSDeterministic as PublicKey;
use blind_rsa_signatures::Signature;
use serde::{Deserialize, Serialize};

const DAY_MS: u64 = 86_400_000;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct Certificate {
    pub account_id: String,
    pub expires_at_ms: u64,
    pub signature_b64: String,
}

pub struct Issuer {
    pub(super) key: PublicKey,
}

impl Issuer {
    pub fn new(public_key_b64: &str) -> Result<Self, String> {
        let key = PublicKey::from_der(&decode(public_key_b64, 1100)?)
            .map_err(|_| "invalid PLUS issuer key")?;
        if key.components().n().len() < 256 {
            return Err("PLUS issuer requires RSA-2048 or stronger".into());
        }
        Ok(Self { key })
    }

    /// The receiver supplies the account established by authenticated peer proof.
    pub fn verify(
        &self,
        certificate: &Certificate,
        account_id: &str,
        now_ms: u64,
    ) -> Result<(), String> {
        if certificate.account_id != account_id {
            return Err("PLUS certificate belongs to another account".into());
        }
        if certificate.expires_at_ms <= now_ms || !certificate.expires_at_ms.is_multiple_of(DAY_MS)
        {
            return Err("PLUS certificate expired or has invalid expiry".into());
        }
        let message = subject_message(account_id)?;
        let metadata = public_metadata(certificate.expires_at_ms);
        let key = self
            .key
            .derive_public_key_for_metadata(&metadata)
            .map_err(|_| "invalid PLUS certificate metadata")?;
        let signature = Signature(decode(&certificate.signature_b64, 700)?);
        key.verify(&signature, None, message, Some(&metadata))
            .map_err(|_| "invalid PLUS certificate signature".into())
    }
}

pub(super) fn subject_message(account_id: &str) -> Result<Vec<u8>, String> {
    if account_id.len() != 64
        || !account_id
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        return Err("invalid PLUS account identity".into());
    }
    Ok(format!("mosh-plus-subject-v1\0{account_id}").into_bytes())
}

pub(super) fn public_metadata(expires_at_ms: u64) -> Vec<u8> {
    format!("mosh-plus-devnet-v1\0mosh-plus-30d\0{expires_at_ms}").into_bytes()
}

pub(super) fn decode(value: &str, limit: usize) -> Result<Vec<u8>, String> {
    if value.len() > limit {
        return Err("PLUS proof exceeds size limit".into());
    }
    STANDARD
        .decode(value)
        .map_err(|_| "invalid PLUS proof encoding".into())
}
