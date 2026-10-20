use base64::{engine::general_purpose::STANDARD, Engine};
use blind_rsa_signatures::pbrsa::PartiallyBlindPublicKeySha384PSSDeterministic as PublicKey;
use blind_rsa_signatures::Signature;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

const DAY_MS: u64 = 86_400_000;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct Certificate {
    pub account_id: String,
    pub expires_at_ms: u64,
    pub signature_b64: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mainnet: Option<MainnetClaims>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct MainnetClaims {
    pub issuer_key_id: String,
    pub valid_from_ms: u64,
}

pub struct Issuer {
    pub(super) key: PublicKey,
    pub(super) mainnet_key_id: Option<String>,
}

impl Issuer {
    pub fn new(public_key_b64: &str) -> Result<Self, String> {
        let key = PublicKey::from_der(&decode(public_key_b64, 1100)?)
            .map_err(|_| "invalid PLUS issuer key")?;
        if key.components().n().len() < 256 {
            return Err("PLUS issuer requires RSA-2048 or stronger".into());
        }
        Ok(Self {
            key,
            mainnet_key_id: None,
        })
    }

    pub fn mainnet(public_key_b64: &str) -> Result<Self, String> {
        let mut issuer = Self::new(public_key_b64)?;
        issuer.mainnet_key_id = Some(hex::encode(Sha256::digest(public_key_b64.as_bytes())));
        Ok(issuer)
    }

    /// The receiver supplies the account established by authenticated peer proof.
    pub fn verify(
        &self,
        certificate: &Certificate,
        account_id: &str,
        now_ms: u64,
    ) -> Result<(), String> {
        self.verify_claims(certificate, account_id)?;
        if certificate.expires_at_ms <= now_ms
            || certificate
                .mainnet
                .as_ref()
                .is_some_and(|claims| claims.valid_from_ms > now_ms)
        {
            return Err("PLUS certificate outside its paid interval".into());
        }
        Ok(())
    }

    /// Check queued certificates without treating a future paid interval as active.
    pub fn verify_claims(&self, certificate: &Certificate, account_id: &str) -> Result<(), String> {
        if certificate.account_id != account_id {
            return Err("PLUS certificate belongs to another account".into());
        }
        if certificate.expires_at_ms == 0 || !certificate.expires_at_ms.is_multiple_of(DAY_MS) {
            return Err("PLUS certificate expired or has invalid expiry".into());
        }
        let message = subject_message(account_id)?;
        match (&self.mainnet_key_id, &certificate.mainnet) {
            (None, None) => {}
            (Some(key_id), Some(claims))
                if key_id == &claims.issuer_key_id
                    && claims.valid_from_ms.is_multiple_of(DAY_MS)
                    && claims.valid_from_ms < certificate.expires_at_ms => {}
            _ => return Err("PLUS certificate network/issuer mismatch".into()),
        }
        if let Some(claims) = &certificate.mainnet {
            let duration = certificate.expires_at_ms - claims.valid_from_ms;
            if !(30 * DAY_MS..=31 * DAY_MS).contains(&duration) {
                return Err("invalid PLUS certificate paid interval".into());
            }
        }
        let metadata = claims_metadata(certificate.expires_at_ms, certificate.mainnet.as_ref());
        let key = self
            .key
            .derive_public_key_for_metadata(&metadata)
            .map_err(|_| "invalid PLUS certificate metadata")?;
        let signature = Signature(decode(&certificate.signature_b64, 700)?);
        key.verify(&signature, None, message, Some(&metadata))
            .map_err(|_| "invalid PLUS certificate signature".into())
    }
}

pub(super) fn claims_metadata(expires_at_ms: u64, claims: Option<&MainnetClaims>) -> Vec<u8> {
    match claims {
        Some(claims) => format!(
            "mosh-plus-mainnet-v1\0mosh-plus-supporter-30d\0{}\0{}\0{expires_at_ms}",
            claims.issuer_key_id, claims.valid_from_ms
        )
        .into_bytes(),
        None => public_metadata(expires_at_ms),
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
