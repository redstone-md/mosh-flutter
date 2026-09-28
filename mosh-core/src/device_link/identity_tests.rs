use super::{
    identity::DeviceIdentity,
    types::{DeviceDescriptor, DeviceLinkErrorKind},
};
use crate::persistence::Persistence;
use ed25519_dalek::SigningKey;
use rand::rngs::OsRng;
use std::sync::Arc;

#[test]
fn stale_identity_writer_cannot_restore_a_revoked_device() {
    let dir = std::env::temp_dir().join(format!("mosh-identity-revoke-{}", rand::random::<u64>()));
    std::fs::create_dir_all(&dir).unwrap();
    let store =
        Arc::new(Persistence::open_with_dek(&dir.join("identity.redb"), rand::random()).unwrap());
    let peer = hex::encode(SigningKey::generate(&mut OsRng).verifying_key().as_bytes());
    let mut author = DeviceIdentity::open(store.clone(), &peer).unwrap();
    let target_peer = hex::encode(SigningKey::generate(&mut OsRng).verifying_key().as_bytes());
    let target = DeviceDescriptor::new(&SigningKey::generate(&mut OsRng), &target_peer);
    let roster = author
        .roster()
        .extend(target.clone(), &author.key())
        .unwrap();
    author.adopt_roster(roster).unwrap();
    let mut stale = DeviceIdentity::open(store.clone(), &author.device().moss_peer_id).unwrap();
    let revoked = author
        .roster()
        .revoke(&target.device_id, &author.key())
        .unwrap();
    author.adopt_roster(revoked).unwrap();
    let error = stale
        .update(stale.record.clone())
        .expect_err("a stale owner must not overwrite removal");
    assert_eq!(error.kind, DeviceLinkErrorKind::Busy);
    stale.reload().unwrap();
    assert_eq!(
        stale.roster().devices().unwrap(),
        vec![author.device().clone()]
    );
    drop(author);
    drop(stale);
    drop(store);
    std::fs::remove_dir_all(dir).unwrap();
}
