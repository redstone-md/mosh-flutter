use super::*;
use ed25519_dalek::{Signer, SigningKey};

#[test]
fn encoded_and_loaded_keys_share_only_exact_successful_signatures() {
    let key = SigningKey::generate(&mut rand::rngs::OsRng);
    let public = key.verifying_key();
    let encoded = hex::encode(public.as_bytes());
    let signed = key.sign(b"message");
    let signature = hex::encode(signed.to_bytes());
    let before = test_count();
    verify(&encoded, &signature, b"message").unwrap();
    assert_eq!(test_count(), before + 1);
    verify_key(&public, &signed, b"message").unwrap();
    assert_eq!(test_count(), before + 1);
    let other = SigningKey::generate(&mut rand::rngs::OsRng).verifying_key();
    for (key, signature, input) in [
        (public, signature.clone(), b"changed".as_slice()),
        (other, signature.clone(), b"message".as_slice()),
        (public, "0".repeat(128), b"message".as_slice()),
    ] {
        let before = test_count();
        for _ in 0..2 {
            assert!(verify(&hex::encode(key.as_bytes()), &signature, input).is_err());
        }
        assert_eq!(test_count(), before + 2, "failed checks must not be cached");
    }
    let before = test_count();
    verify(&encoded, &signature, b"message").unwrap();
    assert_eq!(test_count(), before);
    let changed = hex::encode(key.sign(b"changed").to_bytes());
    verify(&encoded, &changed, b"changed").unwrap();
    assert_eq!(test_count(), before + 1);
}

#[test]
fn malformed_encodings_and_weak_keys_are_rejected() {
    let key = SigningKey::generate(&mut rand::rngs::OsRng).verifying_key();
    for signature in ["", "not-hex", "00"] {
        assert!(verify(&hex::encode(key.as_bytes()), signature, b"message").is_err());
    }
    assert!(verify("not-hex", &"0".repeat(128), b"message").is_err());
    let invalid = (0u8..=255)
        .map(|byte| [byte; 32])
        .find(|bytes| VerifyingKey::from_bytes(bytes).is_err())
        .unwrap();
    assert!(verify(&hex::encode(invalid), &"0".repeat(128), b"message").is_err());
    let mut identity_point = [0; 32];
    identity_point[0] = 1;
    let weak = VerifyingKey::from_bytes(&identity_point).unwrap();
    assert!(weak.is_weak());
    for _ in 0..2 {
        assert!(verify_key(&weak, &Signature::from_bytes(&[0; 64]), b"message").is_err());
        assert!(verify(&hex::encode(identity_point), &"0".repeat(128), b"message").is_err());
    }
}

#[test]
fn concurrent_and_nested_checks_preserve_success_and_fact_namespaces() {
    let key = SigningKey::generate(&mut rand::rngs::OsRng);
    let encoded = hex::encode(key.verifying_key().as_bytes());
    let signature = hex::encode(key.sign(b"message").to_bytes());
    let verify_many = || {
        for _ in 0..20 {
            verify(&encoded, &signature, b"message").unwrap();
        }
    };
    std::thread::scope(|scope| {
        for _ in 0..8 {
            scope.spawn(verify_many);
        }
    });
    let digest = rand::random();
    for _ in 0..2 {
        assert!(verify_cached(Fact::Signature(digest), || Err("invalid".into())).is_err());
    }
    verify_cached(Fact::Signature(digest), || {
        verify(&encoded, &signature, b"message")
    })
    .unwrap();
    verify_cached(Fact::Signature(digest), || {
        panic!("successful fact was lost")
    })
    .unwrap();
    assert!(verify_cached(Fact::Certificate(digest), || Err("different fact".into())).is_err());
}

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
