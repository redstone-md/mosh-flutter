//! Bounded successful cryptographic facts, independent of current permissions.
use ed25519_dalek::{Signature, VerifyingKey};
use sha2::{Digest, Sha256};
use std::{
    collections::{HashSet, VecDeque},
    sync::{LazyLock, Mutex},
};

const CAPACITY: usize = 4096;
static VERIFIED: LazyLock<VerificationCache> = LazyLock::new(VerificationCache::default);

#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub(crate) enum Fact {
    Signature([u8; 32]),
    Certificate([u8; 32]),
}

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
    static CHECKS: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
}

#[cfg(test)]
pub(crate) fn test_count() -> usize {
    CHECKS.get()
}

#[cfg(test)]
fn record_verification() {
    CHECKS.set(CHECKS.get() + 1);
}

/// Cache only timeless math; callers still check live membership and authorization.
pub(crate) fn verify_cached(
    fact: Fact,
    check: impl FnOnce() -> Result<(), String>,
) -> Result<(), String> {
    if VERIFIED.contains(fact) {
        return Ok(());
    }
    // No lock is held during verification. Concurrent misses may verify twice.
    check()?;
    VERIFIED.remember(fact);
    Ok(())
}

pub(crate) fn verify(key: &str, signature: &str, input: &[u8]) -> Result<(), String> {
    let mut bytes = [0; 32];
    hex::decode_to_slice(key, &mut bytes).map_err(|e| e.to_string())?;
    let mut signed = [0; 64];
    hex::decode_to_slice(signature, &mut signed).map_err(|e| e.to_string())?;
    verify_with(&bytes, &Signature::from_bytes(&signed), input, || {
        VerifyingKey::from_bytes(&bytes).map_err(|e| e.to_string())
    })
}

pub(crate) fn verify_key(
    key: &VerifyingKey,
    signature: &Signature,
    input: &[u8],
) -> Result<(), String> {
    verify_with(key.as_bytes(), signature, input, || Ok(*key))
}

fn verify_with(
    key_bytes: &[u8; 32],
    signature: &Signature,
    input: &[u8],
    key: impl FnOnce() -> Result<VerifyingKey, String>,
) -> Result<(), String> {
    let mut digest = Sha256::new();
    // The key and signature have fixed 32/64-byte lengths; the rest is the input.
    digest.update(key_bytes);
    digest.update(signature.to_bytes());
    digest.update(input);
    let fingerprint = Fact::Signature(digest.finalize().into());
    verify_cached(fingerprint, || {
        let key = key()?;
        if key.is_weak() {
            return Err("weak signing key".into());
        }
        #[cfg(test)]
        record_verification();
        key.verify_strict(input, signature)
            .map_err(|e| e.to_string())
    })
}

#[cfg(test)]
mod tests;
