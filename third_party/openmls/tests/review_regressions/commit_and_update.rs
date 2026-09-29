use std::{cell::Cell, io};

use openmls::prelude::*;
use openmls_basic_credential::SignatureKeyPair;
use openmls_rust_crypto::OpenMlsRustCrypto;
use openmls_traits::{
    random::OpenMlsRand,
    signatures::{Signer, SignerError},
    OpenMlsProvider,
};

#[derive(Default)]
struct FailingRandom {
    inner: OpenMlsRustCrypto,
    fail: Cell<bool>,
}

impl OpenMlsRand for FailingRandom {
    type Error = io::Error;

    fn random_array<const N: usize>(&self) -> Result<[u8; N], Self::Error> {
        if self.fail.get() {
            return Err(io::Error::other("injected randomness failure"));
        }
        self.inner.rand().random_array().map_err(io::Error::other)
    }

    fn random_vec(&self, len: usize) -> Result<Vec<u8>, Self::Error> {
        if self.fail.get() {
            return Err(io::Error::other("injected randomness failure"));
        }
        self.inner.rand().random_vec(len).map_err(io::Error::other)
    }
}

#[derive(Default)]
struct Provider {
    inner: OpenMlsRustCrypto,
    random: FailingRandom,
}

impl OpenMlsProvider for Provider {
    type CryptoProvider = <OpenMlsRustCrypto as OpenMlsProvider>::CryptoProvider;
    type RandProvider = FailingRandom;
    type StorageProvider = <OpenMlsRustCrypto as OpenMlsProvider>::StorageProvider;

    fn crypto(&self) -> &Self::CryptoProvider {
        self.inner.crypto()
    }

    fn rand(&self) -> &Self::RandProvider {
        &self.random
    }

    fn storage(&self) -> &Self::StorageProvider {
        self.inner.storage()
    }
}

fn new_group(provider: &Provider, policy: WireFormatPolicy) -> (MlsGroup, SignatureKeyPair) {
    let ciphersuite = Ciphersuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;
    let (credential, signer) = openmls::prelude::test_utils::new_credential(
        provider,
        b"Alice",
        ciphersuite.signature_algorithm(),
    );
    let config = MlsGroupCreateConfig::builder()
        .ciphersuite(ciphersuite)
        .wire_format_policy(policy)
        .build();
    let group = MlsGroup::new(provider, &signer, &config, credential).unwrap();
    (group, signer)
}

#[test]
fn failed_conversion_does_not_stage_a_commit() {
    let provider = Provider::default();
    let (mut group, signer) = new_group(&provider, MIXED_CIPHERTEXT_WIRE_FORMAT_POLICY);
    let group_id = group.group_id().clone();
    let complete = group
        .commit_builder()
        .load_psks(provider.storage())
        .unwrap()
        .build(provider.rand(), provider.crypto(), &signer, |_| true)
        .unwrap();
    provider.random.fail.set(true);
    assert!(complete.stage_commit(&provider).is_err());
    assert!(group.pending_commit().is_none());
    let restored = MlsGroup::load(provider.storage(), &group_id)
        .unwrap()
        .unwrap();
    assert!(restored.pending_commit().is_none());
    assert_eq!(restored.epoch(), group.epoch());
    provider.random.fail.set(false);
    group
        .self_update(&provider, &signer, LeafNodeParameters::default())
        .unwrap();
    group.merge_pending_commit(&provider).unwrap();
}

#[test]
fn successful_staging_survives_reload_in_both_wire_formats() {
    for policy in [
        PURE_PLAINTEXT_WIRE_FORMAT_POLICY,
        MIXED_CIPHERTEXT_WIRE_FORMAT_POLICY,
    ] {
        let provider = Provider::default();
        let (mut group, signer) = new_group(&provider, policy);
        let old_epoch = group.epoch();
        group
            .self_update(&provider, &signer, LeafNodeParameters::default())
            .unwrap();
        let mut restored = MlsGroup::load(provider.storage(), group.group_id())
            .unwrap()
            .unwrap();
        assert!(restored.pending_commit().is_some());
        restored.merge_pending_commit(&provider).unwrap();
        assert!(restored.epoch() > old_epoch);
    }
}

struct FailingSigner(SignatureScheme);

impl Signer for FailingSigner {
    fn sign(&self, _: &[u8]) -> Result<Vec<u8>, SignerError> {
        Err(SignerError::SigningError)
    }

    fn signature_scheme(&self) -> SignatureScheme {
        self.0
    }
}

#[test]
fn failed_leaf_signature_does_not_store_a_private_key() {
    let provider = Provider::default();
    let (mut group, signer) = new_group(&provider, PURE_PLAINTEXT_WIRE_FORMAT_POLICY);
    let before = provider.storage().values.read().unwrap().clone();
    let leaf_before = group.own_leaf_node().unwrap().clone();
    let failing_signer = FailingSigner(signer.signature_scheme());
    assert!(group
        .propose_self_update(&provider, &failing_signer, LeafNodeParameters::default())
        .is_err());
    assert_eq!(group.own_leaf_node().unwrap(), &leaf_before);
    assert!(
        *provider.storage().values.read().unwrap() == before,
        "storage changed on failed signature"
    );
}
