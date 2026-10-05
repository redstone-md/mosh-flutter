use super::*;
use crate::conversation::history::StoredMessage;

#[test]
fn persisted_message_round_trips_attachment_and_call() {
    let msg = ChatMessage {
        metadata: None,
        from_device: "alice".into(),
        body: String::new(),
        message_id: Some("123-000000".into()),
        sent_at_ms: Some(123),
        attachment: Some(AttachmentDescriptor {
            attachment_id: "a1".into(),
            content_hash: "abc123".into(),
            file_name: "photo.bin".into(),
            mime: "image/png".into(),
            total_size: 42,
            thumbnail_b64: None,
            voice: None,
        }),
        call_event: Some(CallEvent {
            kind: "completed".into(),
            duration_ms: 9000,
            call_id: "c1".into(),
        }),
        delivery_status: Some(MessageDeliveryStatus::Failed),
        delivery_error: Some("publish failed".into()),
        retryable: Some(true),
        retry_count: Some(2),
        read: None,
    };
    let pm = StoredMessage {
        conversation_id: "conv".into(),
        sent_at_ms: 123,
        message_id: "123-000000".into(),
        message: msg,
        attachment_manifest: None,
    };
    let bytes = serde_json::to_vec(&pm).unwrap();
    let back: StoredMessage<ChatMessage> = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(back.message.attachment.unwrap().file_name, "photo.bin");
    let ce = back.message.call_event.unwrap();
    assert_eq!(ce.kind, "completed");
    assert_eq!(ce.duration_ms, 9000);
    assert_eq!(back.message.retry_count, Some(2));
    assert_eq!(back.message.read, None);
}

// The cap keeps a long-lived DM's record bounded: past the cap, the
// NEWEST ids are the ones that stay.
#[test]
fn pruned_read_ids_keep_the_newest() {
    let ids: Vec<String> = (0..READ_HISTORY_KEEP + 3)
        .map(|i| format!("m{i:06}"))
        .collect();
    let kept = prune_read_ids(&ids);
    assert_eq!(kept.len(), READ_HISTORY_KEEP, "the cap holds");
    assert_eq!(kept[0], "m000003", "the oldest ids are dropped");
    assert_eq!(
        kept.last().map(String::as_str),
        Some(format!("m{:06}", READ_HISTORY_KEEP + 2).as_str()),
        "the newest id survives"
    );
}

// The read-receipt persistence story: `read` and `read_message_ids` are
// additive `#[serde(default)]` fields, so a session record a build
// before the feature wrote still loads — with no read state.
#[test]
fn a_legacy_record_without_read_state_still_loads() {
    let legacy = serde_json::json!({
        "role_is_alice": true,
        "display_name": "Alice",
        "participant_id": "p",
        "session_id": "s",
        "mesh_id": "m",
        "fingerprint": "f",
        "invite_uri": null,
        "signer_public": [1, 2, 3],
        "group_id": [],
        "listen_port": 0,
        "static_peer": null
    });
    let record: PersistedSession =
        serde_json::from_value(legacy).expect("a pre-receipts record still loads");
    assert_eq!(record.peer_moss_id, None);
    assert!(
        record.read_message_ids.is_empty(),
        "no read state is persisted yet"
    );
}
