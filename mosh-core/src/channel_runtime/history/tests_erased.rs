use super::{tests::*, *};
use crate::{
    message_deletion::{cipher, protocol::DeletionMessage, DeleteScope},
    moss_ffi::MOSS_TEST_LOCK,
};
use ed25519_dalek::SigningKey;

#[test]
fn verified_erasure_replaces_a_durable_partial_without_reassembling_deleted_bytes() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut author = Fixture::new();
    author.join("mid-fragment-delete");
    let sent = author
        .runtime
        .send("mid-fragment-delete", "\u{0001}".repeat(4090))
        .unwrap();
    let source_message = author.runtime.poll("mid-fragment-delete").unwrap().messages[0].clone();
    let source_key = author
        .runtime
        .channels
        .get("mid-fragment-delete")
        .unwrap()
        .node
        .identity_signer()
        .unwrap()
        .clone();
    let record = ChannelRecord {
        message_id: sent.message_id.clone(),
        sent_at_ms: source_message.sent_at_ms.unwrap(),
        from_device: source_message.from_device,
        from_fingerprint: source_message.from_fingerprint,
        content: records::Content::Text(source_message.body),
        origin: source_message.metadata.unwrap().origin,
        legacy_id_absent: false,
    };
    author
        .runtime
        .delete_messages(
            "mid-fragment-delete",
            &[sent.message_id],
            DeleteScope::ForEveryone,
        )
        .unwrap();
    let deletion = author
        .runtime
        .channels
        .get("mid-fragment-delete")
        .unwrap()
        .deletions
        .records
        .values()
        .next()
        .unwrap()
        .clone();
    drop(author);
    let mut reader = Fixture::new();
    reader.join("mid-fragment-delete");
    let holder = SigningKey::from_bytes(&[13; 32]);
    reader.offer_rows(
        "mid-fragment-delete",
        &holder,
        std::slice::from_ref(&record),
    );
    reader.journal("mid-fragment-delete", &holder);
    let bytes = serde_json::to_vec(&record).unwrap();
    let manifest = reader.manifest("mid-fragment-delete");
    reader.deliver(
        "mid-fragment-delete",
        &holder,
        HistoryMessage::Page {
            manifest: manifest.clone(),
            total: 1,
            offset: 0,
            records: Vec::new(),
            fragment: Some(crate::conversation::recovery::fragment::fragment(&bytes, 0).unwrap()),
        },
    );
    assert!(reader
        .runtime
        .poll("mid-fragment-delete")
        .unwrap()
        .messages
        .is_empty());
    reader.restart();
    let erased = ChannelRecord {
        content: records::Content::Erased {
            binding_digest: record.binding_digest().unwrap(),
            deletion_key: deletion.key.clone(),
        },
        ..record
    };
    let page = HistoryMessage::Page {
        manifest,
        total: 1,
        offset: 0,
        records: vec![erased],
        fragment: None,
    };
    reader.deliver("mid-fragment-delete", &holder, page.clone());
    assert_ne!(
        reader
            .runtime
            .poll("mid-fragment-delete")
            .unwrap()
            .history_sync
            .unwrap()
            .state,
        HistorySyncState::Complete
    );
    let frame = cipher::seal_channel(
        "channel:mid-fragment-delete",
        &source_key,
        &DeletionMessage::State {
            records: vec![deletion],
            next: None,
        },
    )
    .unwrap();
    inbox::deliver(MossReceivedMessage {
        channel: "channel-blob/mid-fragment-delete".into(),
        payload: serde_json::to_vec(&ChannelBlobEnvelope::MessageDeletion { frame }).unwrap(),
    });
    reader.runtime.poll("mid-fragment-delete").unwrap();
    reader.deliver("mid-fragment-delete", &holder, page);
    let snapshot = reader.runtime.poll("mid-fragment-delete").unwrap();
    assert_eq!(snapshot.messages.len(), 1);
    assert!(snapshot.messages[0].body.is_empty());
    assert!(snapshot.messages[0]
        .metadata
        .as_ref()
        .unwrap()
        .deletion
        .is_some());
    assert_eq!(
        snapshot.history_sync.unwrap().state,
        HistorySyncState::Complete
    );
    reader.restart();
    assert!(
        reader.runtime.poll("mid-fragment-delete").unwrap().messages[0]
            .body
            .is_empty()
    );
}
