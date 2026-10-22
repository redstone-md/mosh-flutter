use super::identity::{test_key_construction_count, DeviceIdentity};
use crate::{persistence::Persistence, test_temp_directory::TempDirectory};
use ed25519_dalek::{Signer, SigningKey};
use std::sync::Arc;

fn fixture(seed: u8) -> (TempDirectory, Arc<Persistence>, String) {
    let directory = TempDirectory::new("mosh-identity-key");
    let store =
        Arc::new(Persistence::open_with_dek(&directory.path().join("history"), [69; 32]).unwrap());
    let peer = hex::encode(
        SigningKey::from_bytes(&[seed; 32])
            .verifying_key()
            .as_bytes(),
    );
    (directory, store, peer)
}

#[test]
fn account_proof_creation_constructs_the_identity_key_once_per_load() {
    let (_directory, store, peer) = fixture(18);
    let subject = "29".repeat(32);
    let create = || {
        crate::message_deletion::ownership::create(Some(&store), Some(&peer), &subject)
            .unwrap()
            .unwrap()
    };
    let expected = create();
    let before = test_key_construction_count();
    for _ in 0..10 {
        assert_eq!(create(), expected);
        crate::message_deletion::ownership::verify(&expected, &subject).unwrap();
    }
    assert_eq!(
        test_key_construction_count() - before,
        10,
        "each freshly loaded identity should construct its signing key once"
    );
}

#[test]
fn repeated_key_use_preserves_signatures_without_public_key_reconstruction() {
    let (_directory, store, peer) = fixture(18);
    let identity = DeviceIdentity::open(store, &peer).unwrap();
    let expected = SigningKey::from_bytes(&identity.record.seed);
    let signature = expected.sign(b"identity key reuse");
    let before = test_key_construction_count();
    for _ in 0..10 {
        let key = identity.key();
        assert_eq!(key.verifying_key(), expected.verifying_key());
        assert_eq!(key.sign(b"identity key reuse"), signature);
    }
    assert_eq!(test_key_construction_count(), before);
}

#[test]
fn direct_record_seed_edits_never_use_the_previous_key() {
    let (_directory, store, peer) = fixture(18);
    let mut identity = DeviceIdentity::open(store, &peer).unwrap();
    let original = identity.record.seed;
    identity.record.seed = [11; 32];
    let expected = SigningKey::from_bytes(&identity.record.seed);
    assert_eq!(identity.key().verifying_key(), expected.verifying_key());
    assert_eq!(identity.key().sign(b"changed"), expected.sign(b"changed"));
    identity.record.seed = original;
    assert_eq!(
        identity.key().verifying_key(),
        SigningKey::from_bytes(&original).verifying_key()
    );
}

#[test]
fn committed_and_reloaded_records_install_their_own_signing_key() {
    let (_directory, store, peer) = fixture(18);
    let (_other_directory, other_store, _) = fixture(18);
    let mut identity = DeviceIdentity::open(store.clone(), &peer).unwrap();
    let other = DeviceIdentity::open(other_store, &peer).unwrap();
    let expected = other.key().verifying_key();
    identity.update(other.record.clone()).unwrap();
    let before = test_key_construction_count();
    assert_eq!(identity.key().verifying_key(), expected);
    assert_eq!(test_key_construction_count(), before);
    identity.record.seed = [11; 32];
    identity.reload().unwrap();
    let before = test_key_construction_count();
    assert_eq!(identity.key().verifying_key(), expected);
    assert_eq!(test_key_construction_count(), before);
    assert!(DeviceIdentity::open(store, &"ff".repeat(32)).is_err());
}

#[test]
fn another_owners_record_replacement_refreshes_the_loaded_key() {
    let (_directory, store, peer) = fixture(18);
    let (_other_directory, other_store, _) = fixture(18);
    let mut reader = DeviceIdentity::open(store.clone(), &peer).unwrap();
    let mut writer = DeviceIdentity::open(store, &peer).unwrap();
    let other = DeviceIdentity::open(other_store, &peer).unwrap();
    let expected = other.key();
    writer.update(other.record.clone()).unwrap();
    reader.reload().unwrap();
    let before = test_key_construction_count();
    assert_eq!(reader.key().verifying_key(), expected.verifying_key());
    assert_eq!(reader.key().sign(b"reloaded"), expected.sign(b"reloaded"));
    assert_eq!(test_key_construction_count(), before);
}

#[test]
fn an_invalid_committed_seed_still_fails_fresh_validation() {
    let (_directory, store, peer) = fixture(18);
    let mut identity = DeviceIdentity::open(store.clone(), &peer).unwrap();
    let mut record = identity.record.clone();
    record.seed = [11; 32];
    identity.update(record).unwrap();
    let expected = SigningKey::from_bytes(&[11; 32]);
    assert_eq!(identity.key().verifying_key(), expected.verifying_key());
    assert_eq!(
        identity.reload().unwrap_err().kind,
        super::types::DeviceLinkErrorKind::InvalidRoster
    );
    assert!(crate::message_deletion::ownership::create(
        Some(&store),
        Some(&peer),
        &"29".repeat(32)
    )
    .is_err());
}

#[test]
fn a_previously_used_key_cannot_bypass_fresh_local_revocation() {
    let (_root_directory, root_store, root_peer) = fixture(18);
    let (_linked_directory, store, peer) = fixture(19);
    let root = DeviceIdentity::open(root_store, &root_peer).unwrap();
    let mut linked = DeviceIdentity::open(store.clone(), &peer).unwrap();
    let roster = root
        .roster()
        .extend(linked.device().clone(), &root.key())
        .unwrap();
    let mut record = linked.record.clone();
    record.roster = roster.clone();
    record.account_certificate = Some(
        super::account_certificate::AccountCertificate::root(&root.key())
            .issue(&linked.device().signing_public_key, &root.key())
            .unwrap(),
    );
    linked.update(record).unwrap();
    let proof =
        || crate::message_deletion::ownership::create(Some(&store), Some(&peer), &"29".repeat(32));
    assert!(proof().unwrap().is_some());
    linked
        .adopt_roster(
            roster
                .revoke(&linked.device().device_id, &root.key())
                .unwrap(),
        )
        .unwrap();
    assert!(matches!(
        proof(),
        Err(crate::message_deletion::DeletionError::Revoked)
    ));
}
