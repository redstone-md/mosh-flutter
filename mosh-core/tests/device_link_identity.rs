use std::sync::Arc;

use mosh_core::device_link::identity::DeviceIdentity;
use mosh_core::device_link::types::DeviceLinkErrorKind;
use mosh_core::persistence::Persistence;

#[test]
fn a_device_keeps_its_user_and_key_without_touching_existing_history() {
    let path =
        std::env::temp_dir().join(format!("mosh-link-identity-{}.redb", rand::random::<u64>()));
    let peer = hex::encode(
        ed25519_dalek::SigningKey::from_bytes(&[17; 32])
            .verifying_key()
            .as_bytes(),
    );
    let db = Arc::new(Persistence::open_with_dek(&path, [73; 32]).unwrap());
    db.put_moss_identity(b"existing transport identity")
        .unwrap();
    db.put_session("existing-dm", b"existing contact").unwrap();
    db.append_message("existing-dm", 123, "message-1", b"existing text")
        .unwrap();
    let identity = DeviceIdentity::open(db.clone(), &peer).unwrap();
    let user_id = identity.roster().user_id();
    let device = identity.device().clone();
    drop(identity);
    drop(db);

    let db = Arc::new(Persistence::open_with_dek(&path, [73; 32]).unwrap());
    let identity = DeviceIdentity::open(db.clone(), &peer).unwrap();
    assert_eq!(identity.roster().user_id(), user_id);
    assert_eq!(identity.device(), &device);
    assert_eq!(identity.roster().devices().unwrap(), vec![device]);
    assert_eq!(
        db.get_moss_identity().unwrap().unwrap(),
        b"existing transport identity"
    );
    assert_eq!(
        db.list_sessions().unwrap(),
        vec![b"existing contact".to_vec()]
    );
    assert_eq!(
        db.list_messages("existing-dm").unwrap(),
        vec![b"existing text".to_vec()]
    );
    drop(identity);
    drop(db);
    std::fs::remove_file(path).unwrap();
}

#[test]
fn corrupt_or_mismatched_local_identity_fails_closed() {
    let path =
        std::env::temp_dir().join(format!("mosh-link-corrupt-{}.redb", rand::random::<u64>()));
    let key = ed25519_dalek::SigningKey::from_bytes(&[17; 32]);
    let peer = hex::encode(key.verifying_key().as_bytes());
    let db = Arc::new(Persistence::open_with_dek(&path, [73; 32]).unwrap());
    let identity = DeviceIdentity::open(db.clone(), &peer).unwrap();
    let device = identity.device().clone();
    drop(identity);
    let other_peer = hex::encode(
        ed25519_dalek::SigningKey::from_bytes(&[18; 32])
            .verifying_key()
            .as_bytes(),
    );
    assert!(
        matches!(DeviceIdentity::open(db.clone(), &other_peer), Err(e) if e.kind == DeviceLinkErrorKind::InvalidRoster)
    );
    assert_eq!(
        DeviceIdentity::open(db.clone(), &peer).unwrap().device(),
        &device
    );
    db.put_device_link(b"corrupt record").unwrap();
    assert!(
        matches!(DeviceIdentity::open(db.clone(), &peer), Err(e) if e.kind == DeviceLinkErrorKind::Storage)
    );
    drop(db);
    std::fs::remove_file(path).unwrap();
}
