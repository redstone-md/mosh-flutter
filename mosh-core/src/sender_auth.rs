//! One transcript signed by both the transport identity and the MLS leaf.
//! Verification precedes MLS decryption, so tampered headers cannot consume
//! a legitimate message's receive ratchet.

use crate::mls_crypto::MlsSessionCrypto;
use crate::org_envelope::{self, OrgContext, OrgSigned};
use ed25519_dalek::{Signature, SigningKey, VerifyingKey};
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
struct BoundPayload {
    version: u8,
    mls_signer: Vec<u8>,
    payload_b64: String,
}

#[derive(Serialize, Deserialize)]
pub(crate) struct SenderProof {
    #[serde(with = "compact_identity")]
    identity: OrgSigned,
    mls_signature: Vec<u8>,
}

// Numeric byte arrays grow again when org controls wrap the proof. Encoding
// only this new protocol's payload keeps invitations below Moss's 64 KiB cap.
mod compact_identity {
    use super::*;

    #[derive(Serialize, Deserialize)]
    struct Wire {
        peer_id: String,
        payload_b64: String,
        sig: Vec<u8>,
    }

    pub(super) fn serialize<S: serde::Serializer>(
        identity: &OrgSigned,
        serializer: S,
    ) -> Result<S::Ok, S::Error> {
        Wire {
            peer_id: identity.peer_id.clone(),
            payload_b64: crate::conversation::encode(&identity.payload),
            sig: identity.sig.clone(),
        }
        .serialize(serializer)
    }

    pub(super) fn deserialize<'de, D: serde::Deserializer<'de>>(
        deserializer: D,
    ) -> Result<OrgSigned, D::Error> {
        let wire = Wire::deserialize(deserializer)?;
        Ok(OrgSigned {
            peer_id: wire.peer_id,
            payload: crate::conversation::decode(&wire.payload_b64)
                .map_err(serde::de::Error::custom)?,
            sig: wire.sig,
        })
    }
}

pub(crate) struct VerifiedSender {
    pub(crate) peer_id: String,
    pub(crate) mls_signer: Vec<u8>,
    pub(crate) payload: Vec<u8>,
}

impl SenderProof {
    pub(crate) fn sign(
        identity: &SigningKey,
        crypto: &MlsSessionCrypto,
        context: &OrgContext,
        payload: Vec<u8>,
    ) -> Result<Self, String> {
        let bound = serde_json::to_vec(&BoundPayload {
            version: 1,
            mls_signer: crypto.signer_public(),
            payload_b64: crate::conversation::encode(&payload),
        })
        .map_err(|error| error.to_string())?;
        let mls_signature = crypto
            .sign_sender_proof(&org_envelope::signing_input(context, &bound))
            .map_err(|error| error.to_string())?;
        Ok(Self {
            identity: org_envelope::sign(identity, context, &bound),
            mls_signature,
        })
    }

    pub(crate) fn verify(&self, context: &OrgContext) -> Result<VerifiedSender, String> {
        org_envelope::verify(&self.identity, context).map_err(|error| error.to_string())?;
        let bound: BoundPayload =
            serde_json::from_slice(&self.identity.payload).map_err(|error| error.to_string())?;
        if bound.version != 1 {
            return Err("unsupported sender proof version".into());
        }
        let bytes: [u8; 32] = bound
            .mls_signer
            .as_slice()
            .try_into()
            .map_err(|_| "invalid MLS signer")?;
        let key = VerifyingKey::from_bytes(&bytes).map_err(|error| error.to_string())?;
        let signature =
            Signature::from_slice(&self.mls_signature).map_err(|error| error.to_string())?;
        key.verify_strict(
            &org_envelope::signing_input(context, &self.identity.payload),
            &signature,
        )
        .map_err(|error| error.to_string())?;
        Ok(VerifiedSender {
            peer_id: self.identity.peer_id.to_lowercase(),
            mls_signer: bound.mls_signer,
            payload: crate::conversation::decode(&bound.payload_b64)
                .map_err(|error| error.to_string())?,
        })
    }
}

#[cfg(test)]
#[path = "sender_auth_tests.rs"]
mod tests;
