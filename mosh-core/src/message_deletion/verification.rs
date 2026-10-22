//! Cryptographic verification is separate from current membership/permissions.
use ed25519_dalek::{Signature, VerifyingKey};
use sha2::{Digest, Sha256};
use std::{
    collections::{HashSet, VecDeque},
    sync::{LazyLock, Mutex},
};

const CAPACITY: usize = 4096;
static VERIFIED: LazyLock<Mutex<VerifiedSignatures>> = LazyLock::new(Mutex::default);

/// Successful, timeless signature facts only; never permissions or roster state.
/// Fixed-size digests retain no message/proof bodies. Eviction only costs a check.
#[derive(Default)]
struct VerifiedSignatures {
    keys: HashSet<[u8; 32]>,
    order: VecDeque<[u8; 32]>,
}

impl VerifiedSignatures {
    fn remember(&mut self, key: [u8; 32]) {
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
    let fingerprint = digest.finalize().into();
    if VERIFIED
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .keys
        .contains(&fingerprint)
    {
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
    VERIFIED
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .remember(fingerprint);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn eviction_keeps_signature_facts_bounded() {
        let mut cache = VerifiedSignatures::default();
        for index in 0..=CAPACITY {
            let key = Sha256::digest(index.to_be_bytes()).into();
            cache.remember(key);
            cache.remember(key);
        }
        assert_eq!(cache.keys.len(), CAPACITY);
        assert_eq!(cache.order.len(), CAPACITY);
        let first: [u8; 32] = Sha256::digest(0_usize.to_be_bytes()).into();
        let last: [u8; 32] = Sha256::digest(CAPACITY.to_be_bytes()).into();
        assert!(!cache.keys.contains(&first));
        assert!(cache.keys.contains(&last));
    }
}
