use super::{
    identity::DeviceIdentity,
    names_wire::{self, NameMessage},
};
use crate::{persistence::Persistence, test_temp_directory::TempDirectory};
use ed25519_dalek::SigningKey;
use std::sync::Arc;

fn identity(dir: &TempDirectory, name: &str, seed: u8) -> DeviceIdentity {
    let store = Arc::new(Persistence::open_with_dek(&dir.path().join(name), [seed; 32]).unwrap());
    let peer = hex::encode(
        SigningKey::from_bytes(&[seed; 32])
            .verifying_key()
            .as_bytes(),
    );
    DeviceIdentity::open(store, &peer).unwrap()
}

#[test]
fn personal_metadata_requires_current_account_recipient_roster_and_signature() {
    let dir = TempDirectory::new("mosh-name-auth");
    let mut root = identity(&dir, "root", 11);
    let mut second = identity(&dir, "second", 12);
    let outsider = identity(&dir, "outsider", 13);
    let linked = root
        .roster()
        .extend(second.device().clone(), &root.key())
        .unwrap();
    root.adopt_roster(linked.clone()).unwrap();
    let mut record = second.record.clone();
    record.roster = linked;
    second.update(record).unwrap();
    let packet = names_wire::seal(
        &root,
        &second.device().device_id,
        NameMessage::Request { after: None },
    )
    .unwrap();
    assert!(names_wire::open(&second, &packet).is_ok());
    assert!(names_wire::open(&root, &packet).is_err());
    assert!(names_wire::open(&outsider, &packet).is_err());
    let mut body: serde_json::Value =
        serde_json::from_slice(packet.strip_prefix(names_wire::PREFIX).unwrap()).unwrap();
    body["message"]["Request"]["after"] = "channel:tampered".into();
    assert!(serde_json::from_value::<NameMessage>(body["message"].clone()).is_ok());
    let mut forged = names_wire::PREFIX.to_vec();
    forged.extend(serde_json::to_vec(&body).unwrap());
    assert!(names_wire::open(&second, &forged).is_err());
    let revoked = root
        .roster()
        .revoke(&second.device().device_id, &root.key())
        .unwrap();
    second.adopt_roster(revoked.clone()).unwrap();
    root.adopt_roster(revoked).unwrap();
    assert!(names_wire::open(&second, &packet).is_err());
    assert!(names_wire::seal(
        &second,
        &root.device().device_id,
        NameMessage::Request { after: None }
    )
    .is_err());
}
