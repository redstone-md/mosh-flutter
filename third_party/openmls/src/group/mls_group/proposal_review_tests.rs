use super::*;
use crate::prelude::{test_utils::new_credential, *};
use openmls_basic_credential::SignatureKeyPair;
use openmls_rust_crypto::OpenMlsRustCrypto;
use openmls_traits::OpenMlsProvider as _;

fn setup(provider: &OpenMlsRustCrypto) -> (MlsGroup, SignatureKeyPair) {
    let ciphersuite = Ciphersuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;
    let (credential, signer) =
        new_credential(provider, b"Alice", ciphersuite.signature_algorithm());
    let config = MlsGroupCreateConfig::builder()
        .ciphersuite(ciphersuite)
        .build();
    let group = MlsGroup::new(provider, &signer, &config, credential).unwrap();
    (group, signer)
}

#[test]
fn by_value_update_is_rejected_without_storage_changes() {
    let provider = OpenMlsRustCrypto::default();
    let (mut group, signer) = setup(&provider);
    let before = provider.storage().values.read().unwrap().clone();
    let result = group.propose(
        &provider,
        &signer,
        Propose::Update(LeafNodeParameters::default()),
        ProposalOrRefType::Proposal,
    );
    assert!(matches!(result, Err(ProposalError::LibraryError(_))));
    assert_eq!(group.pending_proposals().count(), 0);
    assert!(
        *provider.storage().values.read().unwrap() == before,
        "storage changed on rejected update"
    );
}

#[test]
fn reference_update_keeps_requested_encoding() {
    let provider = OpenMlsRustCrypto::default();
    let (mut group, signer) = setup(&provider);
    group
        .propose(
            &provider,
            &signer,
            Propose::Update(LeafNodeParameters::default()),
            ProposalOrRefType::Reference,
        )
        .unwrap();
    let pending = group.pending_proposals().next().unwrap();
    assert_eq!(pending.proposal_or_ref_type(), ProposalOrRefType::Reference);
}
