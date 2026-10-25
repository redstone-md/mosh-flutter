use super::{identity::DeviceIdentity, types::DeviceDescriptor};
use crate::{
    persistence::Persistence, signature_verification::test_count,
    test_temp_directory::TempDirectory,
};
use ed25519_dalek::SigningKey;
use rand::rngs::OsRng;
use std::sync::Arc;

#[test]
fn unchanged_identity_opens_reuse_successful_roster_signatures() {
    let dir = TempDirectory::new("mosh-identity-verification");
    let store =
        Arc::new(Persistence::open_with_dek(&dir.path().join("state.redb"), [91; 32]).unwrap());
    let peer = hex::encode(SigningKey::generate(&mut OsRng).verifying_key().as_bytes());
    let owner = DeviceIdentity::open(store.clone(), &peer).unwrap();
    let expected = serde_json::to_vec(owner.roster()).unwrap();
    let persisted = store.get_device_link().unwrap();
    let before = test_count();
    for _ in 0..10 {
        let reopened = DeviceIdentity::open(store.clone(), &peer).unwrap();
        assert_eq!(serde_json::to_vec(reopened.roster()).unwrap(), expected);
        assert_eq!(reopened.device(), owner.device());
        assert!(!reopened.revoked().unwrap());
    }
    assert_eq!(store.get_device_link().unwrap(), persisted);
    assert_eq!(
        test_count(),
        before,
        "unchanged opens repeated roster signatures"
    );
}

#[test]
fn warmed_identity_checks_reject_tampering_and_observe_local_revocation() {
    let dir = TempDirectory::new("mosh-identity-current-roster");
    let store =
        Arc::new(Persistence::open_with_dek(&dir.path().join("state.redb"), [92; 32]).unwrap());
    let peer = hex::encode(SigningKey::generate(&mut OsRng).verifying_key().as_bytes());
    let mut owner = DeviceIdentity::open(store.clone(), &peer).unwrap();
    let linked_key = SigningKey::generate(&mut OsRng);
    let linked = DeviceDescriptor::new(
        &linked_key,
        &hex::encode(linked_key.verifying_key().as_bytes()),
    );
    owner
        .adopt_roster(owner.roster().extend(linked, &owner.key()).unwrap())
        .unwrap();
    DeviceIdentity::open(store.clone(), &peer).unwrap();
    let mut forged = serde_json::to_value(&owner.record).unwrap();
    forged["roster"]["entries"][0]["device"]["name"] = "forged".into();
    store
        .put_device_link(&serde_json::to_vec(&forged).unwrap())
        .unwrap();
    assert!(DeviceIdentity::open(store.clone(), &peer).is_err());
    let removed = owner
        .roster()
        .revoke(&owner.device().device_id, &linked_key)
        .unwrap();
    let mut record = owner.record.clone();
    record.roster = removed;
    store
        .put_device_link(&serde_json::to_vec(&record).unwrap())
        .unwrap();
    let reopened = DeviceIdentity::open(store, &peer).unwrap();
    assert!(reopened.revoked().unwrap());
    assert!(reopened.account_certificate().is_err());
}
