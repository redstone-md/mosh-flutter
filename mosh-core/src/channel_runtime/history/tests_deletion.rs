use super::{tests::*, *};
use crate::{
    message_deletion::{protocol::DeletionMessage, DeleteScope},
    moss_ffi::MOSS_TEST_LOCK,
};
use ed25519_dalek::SigningKey;

#[test]
fn a_verified_source_journal_is_applied_before_old_content_becomes_visible() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut author = Fixture::new();
    author.join("journal-first");
    let sent = author
        .runtime
        .send("journal-first", "never resurrect".into())
        .unwrap();
    let original = author.runtime.poll("journal-first").unwrap().messages[0].clone();
    author
        .runtime
        .delete_messages(
            "journal-first",
            std::slice::from_ref(&sent.message_id),
            DeleteScope::ForEveryone,
        )
        .unwrap();
    let deletion = author
        .runtime
        .channels
        .get("journal-first")
        .unwrap()
        .deletions
        .records
        .values()
        .next()
        .unwrap()
        .clone();
    let digest = crate::conversation::recovery::manifest::digest(&vec![deletion.clone()]).unwrap();
    drop(author);
    let mut reader = Fixture::new();
    reader.join("journal-first");
    let source = SigningKey::from_bytes(&[16; 32]);
    let record = ChannelRecord {
        message_id: sent.message_id,
        sent_at_ms: original.sent_at_ms.unwrap(),
        from_device: original.from_device,
        from_fingerprint: original.from_fingerprint,
        content: records::Content::Text(original.body),
        origin: original.metadata.unwrap().origin,
        legacy_id_absent: false,
    };
    let key = crate::conversation::recovery::manifest::HistoryKey {
        message_id: record.message_id.clone(),
        sent_at_ms: record.sent_at_ms,
        digest: crate::conversation::recovery::manifest::digest(&record).unwrap(),
    };
    let manifest =
        crate::conversation::recovery::manifest::digest(&(1, "channel:journal-first", vec![key]))
            .unwrap();
    reader.deliver(
        "journal-first",
        &source,
        HistoryMessage::Offer {
            manifest: manifest.clone(),
            total: 1,
            deletion_digest: digest.clone(),
        },
    );
    reader.deliver(
        "journal-first",
        &source,
        HistoryMessage::Page {
            manifest: manifest.clone(),
            total: 1,
            offset: 0,
            records: vec![record.clone()],
            fragment: None,
        },
    );
    assert!(
        reader
            .runtime
            .poll("journal-first")
            .unwrap()
            .messages
            .is_empty(),
        "content cannot precede its prerequisite"
    );
    reader.deliver(
        "journal-first",
        &source,
        HistoryMessage::Journal {
            manifest: manifest.clone(),
            deletion_digest: digest,
            page: DeletionMessage::State {
                records: vec![deletion],
                next: None,
            },
        },
    );
    reader.deliver(
        "journal-first",
        &source,
        HistoryMessage::Page {
            manifest: manifest.clone(),
            total: 1,
            offset: 0,
            records: vec![record],
            fragment: None,
        },
    );
    let snapshot = reader.runtime.poll("journal-first").unwrap();
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
}

#[test]
fn a_source_cannot_finish_a_different_or_incomplete_deletion_journal() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut f = Fixture::new();
    f.join("journal-mismatch");
    let source = SigningKey::from_bytes(&[15; 32]);
    f.deliver(
        "journal-mismatch",
        &source,
        HistoryMessage::Offer {
            manifest: "a".repeat(64),
            total: 0,
            deletion_digest: "b".repeat(64),
        },
    );
    f.deliver(
        "journal-mismatch",
        &source,
        HistoryMessage::Journal {
            manifest: "a".repeat(64),
            deletion_digest: "b".repeat(64),
            page: DeletionMessage::State {
                records: Vec::new(),
                next: None,
            },
        },
    );
    f.deliver(
        "journal-mismatch",
        &source,
        HistoryMessage::Page {
            manifest: "a".repeat(64),
            total: 0,
            offset: 0,
            records: Vec::new(),
            fragment: None,
        },
    );
    let snapshot = f.runtime.poll("journal-mismatch").unwrap();
    assert!(snapshot.messages.is_empty());
    assert_ne!(
        snapshot.history_sync.as_ref().unwrap().state,
        HistorySyncState::Complete
    );
    assert_eq!(
        snapshot.history_sync.unwrap().reason,
        Some(HistorySyncReason::EvidenceMissing)
    );
}
