use base64::{engine::general_purpose::STANDARD, Engine};
use blind_rsa_signatures::{BlindMessage, BlindSignature, BlindingResult, DefaultRng, Secret};
use serde::{Deserialize, Serialize};

use super::{
    certificate::{claims_metadata, decode, subject_message, MainnetClaims},
    Certificate, Issuer,
};

#[derive(Clone, Serialize, Deserialize)]
pub(super) struct PreparedIssuance {
    account_id: String,
    expires_at_ms: u64,
    pub blinded_message_b64: String,
    secret_b64: String,
    #[serde(default)]
    mainnet: Option<MainnetClaims>,
}

impl PreparedIssuance {
    pub(super) fn matches(&self, account: &str, from: Option<u64>, until: Option<u64>) -> bool {
        self.account_id == account
            && Some(self.expires_at_ms) == until
            && self.mainnet.as_ref().map(|c| c.valid_from_ms) == from
            && self.blinded_message_b64.len() <= 700
            && self.secret_b64.len() <= 700
    }
}

impl Issuer {
    pub(super) fn prepare(
        &self,
        account_id: &str,
        expires_at_ms: u64,
    ) -> Result<PreparedIssuance, String> {
        self.prepare_claims(account_id, expires_at_ms, None)
    }

    pub(super) fn prepare_claims(
        &self,
        account_id: &str,
        expires_at_ms: u64,
        mainnet: Option<MainnetClaims>,
    ) -> Result<PreparedIssuance, String> {
        if expires_at_ms == 0 || !expires_at_ms.is_multiple_of(86_400_000) {
            return Err("invalid PLUS issuance expiry".into());
        }
        let metadata = claims_metadata(expires_at_ms, mainnet.as_ref());
        let message = subject_message(account_id)?;
        let key = self
            .key
            .derive_public_key_for_metadata(&metadata)
            .map_err(|_| "invalid PLUS metadata")?;
        let state = key
            .blind(&mut DefaultRng, message, Some(&metadata))
            .map_err(|_| "PLUS blinding failed")?;
        Ok(PreparedIssuance {
            account_id: account_id.to_owned(),
            expires_at_ms,
            blinded_message_b64: STANDARD.encode(state.blind_message.0),
            secret_b64: STANDARD.encode(state.secret.0),
            mainnet,
        })
    }

    pub(super) fn finalize(
        &self,
        prepared: &PreparedIssuance,
        reply: &str,
        now_ms: u64,
    ) -> Result<Certificate, String> {
        let metadata = claims_metadata(prepared.expires_at_ms, prepared.mainnet.as_ref());
        let message = subject_message(&prepared.account_id)?;
        let key = self
            .key
            .derive_public_key_for_metadata(&metadata)
            .map_err(|_| "invalid PLUS metadata")?;
        let state = BlindingResult {
            blind_message: BlindMessage(decode(&prepared.blinded_message_b64, 700)?),
            secret: Secret(decode(&prepared.secret_b64, 700)?),
            msg_randomizer: None,
        };
        let signature = key
            .finalize(
                &BlindSignature(decode(reply, 700)?),
                &state,
                message,
                Some(&metadata),
            )
            .map_err(|_| "invalid PLUS issuance reply")?;
        let certificate = Certificate {
            account_id: prepared.account_id.clone(),
            expires_at_ms: prepared.expires_at_ms,
            signature_b64: STANDARD.encode(signature.0),
            mainnet: prepared.mainnet.clone(),
        };
        self.verify_claims(&certificate, &prepared.account_id)?;
        if certificate.expires_at_ms <= now_ms {
            return Err("PLUS certificate expired".into());
        }
        Ok(certificate)
    }
}
