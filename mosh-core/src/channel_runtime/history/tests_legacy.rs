use super::{tests::*, *};
use crate::conversation::history::StoredMessage;
use crate::moss_ffi::MOSS_TEST_LOCK;
use ed25519_dalek::SigningKey;

#[test]
fn a_missing_original_legacy_id_has_a_stable_alias_without_changing_local_action_ids() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    fixture.join("old-ids");
    let mut message = ChannelMessage {
        metadata: None,
        from_device: "Old label".into(),
        from_fingerprint: "21".repeat(32),
        body: "pre-upgrade".into(),
        message_id: None,
        sent_at_ms: Some(1000),
        attachment: None,
        delivery_status: None,
        delivery_error: None,
        retryable: None,
        retry_count: None,
    };
    let stored = StoredMessage {
        conversation_id: "old-ids".into(),
        sent_at_ms: 1000,
        message_id: "old-local-action".into(),
        message: message.clone(),
        attachment_manifest: None,
        preview_manifest: None,
        history_evidence: None,
    };
    fixture
        .store
        .append_history_message(
            CHANNEL_HISTORY,
            "old-ids",
            1000,
            "old-local-action",
            &serde_json::to_vec(&stored).unwrap(),
        )
        .unwrap();
    fixture.restart();
    let first = fixture.runtime.poll("old-ids").unwrap();
    assert_eq!(
        first.messages[0].message_id.as_deref(),
        Some("old-local-action")
    );
    let record = ChannelRecord::from_stored(&stored).unwrap();
    let canonical_id = record.message_id.clone();
    assert!(record.message_id.starts_with("legacy-"));
    assert_ne!(record.message_id, "old-local-action");
    let holder = SigningKey::from_bytes(&[18; 32]);
    fixture.offer_rows("old-ids", &holder, std::slice::from_ref(&record));
    fixture.journal("old-ids", &holder);
    fixture.deliver(
        "old-ids",
        &holder,
        HistoryMessage::Page {
            manifest: fixture.manifest("old-ids"),
            total: 1,
            offset: 0,
            records: vec![record],
            fragment: None,
        },
    );
    let snapshot = fixture.runtime.poll("old-ids").unwrap();
    assert_eq!(snapshot.messages.len(), 1);
    assert_eq!(
        snapshot.messages[0].message_id.as_deref(),
        Some("old-local-action")
    );
    assert!(snapshot.messages[0]
        .metadata
        .as_ref()
        .is_none_or(|m| m.origin.is_none()));
    assert_eq!(
        snapshot.history_sync.unwrap().state,
        HistorySyncState::Complete
    );
    fixture
        .runtime
        .delete_messages(
            "old-ids",
            &["old-local-action".into()],
            crate::message_deletion::DeleteScope::ForMe,
        )
        .unwrap();
    assert!(fixture.runtime.poll("old-ids").unwrap().messages.is_empty());
    message.body = "different occurrence".into();
    assert_ne!(
        ChannelRecord::from_stored(&StoredMessage { message, ..stored })
            .unwrap()
            .message_id,
        canonical_id
    );
}
