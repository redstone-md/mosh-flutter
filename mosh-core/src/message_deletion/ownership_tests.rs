use super::ownership;
use crate::{
    device_link::identity::DeviceIdentity, persistence::Persistence,
    test_temp_directory::TempDirectory,
};
use std::sync::Arc;

#[test]
fn account_proofs_reveal_neither_device_names_nor_mesh_addresses() {
    let directory = TempDirectory::new("private-account-proof");
    let store =
        Arc::new(Persistence::open_with_dek(&directory.path().join("history"), [77; 32]).unwrap());
    let peer = hex::encode(
        ed25519_dalek::SigningKey::from_bytes(&[19; 32])
            .verifying_key()
            .as_bytes(),
    );
    let identity = DeviceIdentity::open(store.clone(), &peer).unwrap();
    let subject = identity.device().signing_public_key.clone();
    let proof = ownership::create(Some(&store), Some(&peer), &subject)
        .unwrap()
        .unwrap();
    assert_eq!(
        ownership::verify(&proof, &subject).unwrap(),
        identity.roster().user_id()
    );
    assert!(!proof.contains("Desktop"));
    assert!(!proof.contains(&peer));
    assert!(!proof.contains("roster"));
    assert!(ownership::verify(&proof, &"cd".repeat(32)).is_err());
}

#[test]
fn compact_delegations_require_every_authorizing_signature() {
    use crate::device_link::account_certificate::AccountCertificate;
    use ed25519_dalek::SigningKey;
    let root = SigningKey::from_bytes(&[7; 32]);
    let linked = SigningKey::from_bytes(&[8; 32]);
    let third = SigningKey::from_bytes(&[9; 32]);
    let certificate = AccountCertificate::root(&root)
        .issue(&hex::encode(linked.verifying_key().as_bytes()), &root)
        .unwrap();
    assert!(certificate
        .issue(&hex::encode(third.verifying_key().as_bytes()), &third)
        .is_err());
    let delegated = certificate
        .issue(&hex::encode(third.verifying_key().as_bytes()), &linked)
        .unwrap();
    delegated.verify().unwrap();
    let forged = serde_json::to_value(&delegated).unwrap();
    let mut forged = forged;
    forged["root"] = hex::encode(linked.verifying_key().as_bytes()).into();
    assert!(serde_json::from_value::<AccountCertificate>(forged)
        .unwrap()
        .verify()
        .is_err());
}
