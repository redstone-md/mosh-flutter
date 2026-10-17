use super::PlusRuntime;
use crate::test_temp_directory::TempDirectory;
use crate::{device_link::identity::DeviceIdentity, persistence::Persistence};
use ed25519_dalek::{Signer, SigningKey};
use std::sync::Arc;

#[test]
fn unknown_withdrawals_do_not_consume_durable_peer_capacity() {
    let directory = TempDirectory::new("mosh-plus-withdrawal");
    let sender_store =
        Arc::new(Persistence::open_with_dek(&directory.path().join("sender"), [41; 32]).unwrap());
    let peer = "01".repeat(32);
    let identity = DeviceIdentity::open(sender_store.clone(), &peer).unwrap();
    let vector: serde_json::Value =
        serde_json::from_str(include_str!("../../tests/fixtures/plus-public-vector.json")).unwrap();
    let key = vector["public_key"].as_str().unwrap();
    let mut sender = PlusRuntime::open(sender_store, identity.roster().user_id(), key).unwrap();
    sender.set_visible(true).unwrap();
    sender.set_visible(false).unwrap();
    let signer = SigningKey::from_bytes(&[3; 32]);
    let author = hex::encode(signer.verifying_key().as_bytes());
    let frame = sender
        .frame(
            "channel:test",
            &peer,
            &author,
            |bytes| Ok(signer.sign(bytes).to_bytes().to_vec()),
            1_700_000_000_000,
        )
        .unwrap()
        .unwrap();
    let store =
        Arc::new(Persistence::open_with_dek(&directory.path().join("receiver"), [42; 32]).unwrap());
    let mut receiver = PlusRuntime::open(store.clone(), "cd".repeat(32), key).unwrap();
    receiver
        .accept_peer(&frame, "channel:test", &author, &[peer], 1_700_000_000_000)
        .unwrap();
    assert!(
        store.get_plus_record("local-v1").unwrap().is_none(),
        "Unsolicited withdrawals must not allocate persistent peer records"
    );
}
