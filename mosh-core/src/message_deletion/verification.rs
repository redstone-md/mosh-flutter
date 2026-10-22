//! Cryptographic verification is separate from current membership/permissions.
use crate::device_link::account_certificate::AccountCertificate;
use ed25519_dalek::{Signature, VerifyingKey};
use sha2::{Digest, Sha256};
use std::{
    collections::{HashSet, VecDeque},
    sync::{LazyLock, Mutex},
};

const CAPACITY: usize = 4096;
static VERIFIED: LazyLock<VerificationCache> = LazyLock::new(VerificationCache::default);

#[derive(Clone, Copy, PartialEq, Eq, Hash)]
enum Fact {
    Signature([u8; 32]),
    Certificate([u8; 32]),
}

/// Successful, timeless cryptographic facts only; never permissions or roster state.
/// Fixed-size digests retain no message/proof bodies. Eviction only costs a check.
#[derive(Default)]
struct VerifiedFacts {
    keys: HashSet<Fact>,
    order: VecDeque<Fact>,
}

impl VerifiedFacts {
    fn remember(&mut self, key: Fact) {
        if !self.keys.insert(key) {
            return;
        }
        self.order.push_back(key);
        if self.order.len() > CAPACITY {
            if let Some(oldest) = self.order.pop_front() {
                self.keys.remove(&oldest);
            }
        }
    }
}

#[derive(Default)]
struct VerificationCache(Mutex<VerifiedFacts>);

impl VerificationCache {
    fn contains(&self, fact: Fact) -> bool {
        self.0
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .keys
            .contains(&fact)
    }

    fn remember(&self, fact: Fact) {
        self.0
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .remember(fact);
    }
}

#[cfg(test)]
thread_local! {
    static VERIFICATIONS: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
}

#[cfg(test)]
pub(super) fn test_count() -> usize {
    VERIFICATIONS.get()
}

pub(crate) fn verify(key: &str, signature: &str, input: &[u8]) -> Result<(), String> {
    let mut key_bytes = [0; 32];
    hex::decode_to_slice(key, &mut key_bytes).map_err(|e| e.to_string())?;
    let mut digest = Sha256::new();
    digest.update(key_bytes);
    digest.update((signature.len() as u64).to_be_bytes());
    digest.update(signature.as_bytes());
    digest.update(input);
    let fingerprint = Fact::Signature(digest.finalize().into());
    if VERIFIED.contains(fingerprint) {
        return Ok(());
    }
    // No cache lock is held during curve arithmetic. Concurrent misses may
    // verify twice; only successful checks can populate the cache.
    let key = VerifyingKey::from_bytes(&key_bytes).map_err(|e| e.to_string())?;
    if key.is_weak() {
        return Err("weak signing key".into());
    }
    let mut signature_bytes = [0; 64];
    hex::decode_to_slice(signature, &mut signature_bytes).map_err(|e| e.to_string())?;
    let signature = Signature::from_bytes(&signature_bytes);
    #[cfg(test)]
    VERIFICATIONS.set(VERIFICATIONS.get() + 1);
    key.verify_strict(input, &signature)
        .map_err(|e| e.to_string())?;
    VERIFIED.remember(fingerprint);
    Ok(())
}

/// Whole delegation chains are timeless; revocation and account rights are not.
pub(super) fn verify_certificate(certificate: &AccountCertificate) -> Result<(), String> {
    let bytes = serde_json::to_vec(certificate).map_err(|e| e.to_string())?;
    let fingerprint = Fact::Certificate(Sha256::digest(bytes).into());
    if VERIFIED.contains(fingerprint) {
        return Ok(());
    }
    certificate.verify().map_err(|e| e.to_string())?;
    VERIFIED.remember(fingerprint);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn eviction_keeps_signature_facts_bounded() {
        let mut cache = VerifiedFacts::default();
        for index in 0..=CAPACITY {
            let key = Fact::Signature(Sha256::digest(index.to_be_bytes()).into());
            cache.remember(key);
            cache.remember(key);
        }
        assert_eq!(cache.keys.len(), CAPACITY);
        assert_eq!(cache.order.len(), CAPACITY);
        let first: [u8; 32] = Sha256::digest(0_usize.to_be_bytes()).into();
        let last: [u8; 32] = Sha256::digest(CAPACITY.to_be_bytes()).into();
        assert!(!cache.keys.contains(&Fact::Signature(first)));
        assert!(cache.keys.contains(&Fact::Signature(last)));
        assert!(!cache.keys.contains(&Fact::Certificate(last)));
    }

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
