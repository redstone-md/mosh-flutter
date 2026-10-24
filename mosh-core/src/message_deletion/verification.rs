//! Cryptographic verification is separate from current membership/permissions.
#[cfg(test)]
pub(super) use crate::signature_verification::test_count;
pub(crate) use crate::signature_verification::verify;
use crate::{
    device_link::account_certificate::AccountCertificate,
    signature_verification::{verify_cached, Fact},
};
use sha2::{Digest, Sha256};

/// Whole delegation chains are timeless; revocation and account rights are not.
pub(super) fn verify_certificate(certificate: &AccountCertificate) -> Result<(), String> {
    let bytes = serde_json::to_vec(certificate).map_err(|e| e.to_string())?;
    let fingerprint = Fact::Certificate(Sha256::digest(bytes).into());
    verify_cached(fingerprint, || {
        certificate.verify().map_err(|e| e.to_string())
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn changed_delegations_cannot_claim_a_cached_account() {
        use super::super::ownership;
        use ed25519_dalek::SigningKey;
        let root = SigningKey::generate(&mut rand::rngs::OsRng);
        let intermediate = SigningKey::generate(&mut rand::rngs::OsRng);
        let linked = SigningKey::generate(&mut rand::rngs::OsRng);
        let root_key = hex::encode(root.verifying_key().as_bytes());
        let linked_key = hex::encode(linked.verifying_key().as_bytes());
        let certificate = AccountCertificate::root(&root)
            .issue(&hex::encode(intermediate.verifying_key().as_bytes()), &root)
            .unwrap()
            .issue(&linked_key, &intermediate)
            .unwrap();
        let root_proof = ownership::test_proof(&root);
        let same_account = |certificate| {
            let proof = ownership::signed_test_proof(certificate, &linked);
            ownership::same_account(&root_key, Some(&root_proof), &linked_key, Some(&proof))
        };
        assert!(same_account(certificate.clone()));
        for field in ["signature", "key"] {
            let mut encoded = serde_json::to_value(&certificate).unwrap();
            encoded["delegations"][0][field] = if field == "signature" {
                "0".repeat(128).into()
            } else {
                root_key.clone().into()
            };
            let forged = serde_json::from_value(encoded).unwrap();
            assert!(!same_account(forged));
        }
        assert!(same_account(certificate));
    }
}
