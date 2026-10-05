use super::{proof::DevicePacket, types::DeviceMessage, *};
use crate::{
    device_link::identity::DeviceIdentity,
    message_deletion::{MessageMetadata, MessageOrigin},
    persistence::Persistence,
    test_temp_directory::TempDirectory,
};
use std::sync::Arc;

fn fixture() -> (TempDirectory, DeviceIdentity, DeviceMessage) {
    let directory = TempDirectory::new("history-wire-compatibility");
    let store =
        Arc::new(Persistence::open_with_dek(&directory.path().join("store"), [55; 32]).unwrap());
    let signer = ed25519_dalek::SigningKey::from_bytes(&[19; 32]);
    let peer = hex::encode(signer.verifying_key().as_bytes());
    let identity = DeviceIdentity::open(store, &peer).unwrap();
    let origin = MessageOrigin::sign("dm:session", "message", b"content", &signer, None).unwrap();
    let batch = serde_json::from_value::<history::HistoryBatch>(serde_json::json!({
        "session_id": "session", "epoch": null, "request_id": "request", "offset": 0, "total": 1, "manifest": "ab".repeat(32), "fragment": null,
        "records": [{"message_id": "message", "sent_at_ms": 42, "from_device": "sender", "body": "content", "metadata": MessageMetadata { origin: Some(origin), ..Default::default() }}]
    })).unwrap();
    let message = DeviceMessage::HistoryBatch(batch);
    (directory, identity, message)
}

#[test]
fn metadata_restores_after_primary_verification_and_legacy_packets_still_verify() {
    let (_directory, identity, message) = fixture();
    let bytes = DevicePacket::seal(&identity, "recipient", message).unwrap();
    let mut value: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert!(value["message"]["HistoryBatch"]["records"][0]
        .get("metadata")
        .is_none());
    let DeviceMessage::HistoryBatch(batch) =
        DevicePacket::open(&bytes, "recipient").unwrap().message
    else {
        panic!("wrong message");
    };
    assert!(batch.records[0].metadata.as_ref().unwrap().origin.is_some());
    value.as_object_mut().unwrap().remove("history_metadata");
    let DeviceMessage::HistoryBatch(legacy) =
        DevicePacket::open(&serde_json::to_vec(&value).unwrap(), "recipient")
            .unwrap()
            .message
    else {
        panic!("wrong message");
    };
    assert!(legacy.records[0].metadata.is_none());
    assert_eq!(legacy.records[0].body, "content");
}

#[test]
fn metadata_tampering_and_transplanting_between_pages_are_rejected() {
    let (_directory, identity, message) = fixture();
    let bytes = DevicePacket::seal(&identity, "recipient", message.clone()).unwrap();
    let original: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let mut tampered = original.clone();
    tampered["history_metadata"]["records"][0]["origin"]["author"] = "ab".repeat(32).into();
    assert!(DevicePacket::open(&serde_json::to_vec(&tampered).unwrap(), "recipient").is_err());
    let DeviceMessage::HistoryBatch(mut second) = message else {
        panic!("wrong message");
    };
    second.request_id = "another-request".into();
    let bytes =
        DevicePacket::seal(&identity, "recipient", DeviceMessage::HistoryBatch(second)).unwrap();
    let mut transplanted: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    transplanted["history_metadata"] = original["history_metadata"].clone();
    assert!(DevicePacket::open(&serde_json::to_vec(&transplanted).unwrap(), "recipient").is_err());
}

#[test]
fn recovery_and_fragment_metadata_use_the_same_bound_extension() {
    let (_directory, identity, message) = fixture();
    let DeviceMessage::HistoryBatch(mut batch) = message else {
        panic!("wrong message");
    };
    let record = batch.records.remove(0);
    batch.fragment = Some(
        serde_json::from_value(
            serde_json::json!({ "record": record, "body_offset": 0, "body_length": 10 }),
        )
        .unwrap(),
    );
    let packet = DevicePacket::seal(
        &identity,
        "recipient",
        DeviceMessage::RecoveryBatch(recovery::RecoveryBatch { round: 5, batch }),
    )
    .unwrap();
    let DeviceMessage::RecoveryBatch(restored) =
        DevicePacket::open(&packet, "recipient").unwrap().message
    else {
        panic!("wrong message");
    };
    assert!(restored.batch.fragment.unwrap().record.metadata.is_some());
}
