use super::{tests::*, *};
use crate::{
    conversation::recovery::{fragment, manifest::HistoryKey},
    message_deletion::{protocol::DeletionMessage, DeleteScope},
    moss_ffi::MOSS_TEST_LOCK,
};
use ed25519_dalek::SigningKey;

#[test]
fn a_journal_fragment_resumes_after_restart_before_any_old_content_is_visible() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut author = Fixture::new();
    author.join("journal-fragments");
    let mut original = None;
    for index in 0..16 {
        let sent = author
            .runtime
            .send("journal-fragments", format!("erased {index}"))
            .unwrap();
        original.get_or_insert_with(|| {
            author.runtime.poll("journal-fragments").unwrap().messages[0].clone()
        });
        author
            .runtime
            .delete_messages(
                "journal-fragments",
                &[sent.message_id],
                DeleteScope::ForEveryone,
            )
            .unwrap();
    }
    let deletions = author
        .runtime
        .channels
        .get("journal-fragments")
        .unwrap()
        .deletions
        .records
        .values()
        .cloned()
        .collect::<Vec<_>>();
    let digest = crate::conversation::recovery::manifest::digest(&deletions).unwrap();
    let bytes = serde_json::to_vec(&DeletionMessage::State {
        records: deletions,
        next: None,
    })
    .unwrap();
    assert!(bytes.len() > 24_000);
    let original = original.unwrap();
    let record = ChannelRecord {
        message_id: original.message_id.unwrap(),
        sent_at_ms: original.sent_at_ms.unwrap(),
        from_device: original.from_device,
        from_fingerprint: original.from_fingerprint,
        content: records::Content::Text(original.body),
        origin: original.metadata.unwrap().origin,
        legacy_id_absent: false,
    };
    let key = HistoryKey {
        message_id: record.message_id.clone(),
        sent_at_ms: record.sent_at_ms,
        digest: record.binding_digest().unwrap(),
    };
    let manifest = crate::conversation::recovery::manifest::digest(&(
        1,
        "channel:journal-fragments",
        vec![key],
    ))
    .unwrap();
    drop(author);
    let mut reader = Fixture::new();
    reader.join("journal-fragments");
    let source = SigningKey::from_bytes(&[17; 32]);
    reader.deliver(
        "journal-fragments",
        &source,
        HistoryMessage::Offer {
            manifest: manifest.clone(),
            total: 1,
            deletion_digest: digest.clone(),
        },
    );
    reader.deliver(
        "journal-fragments",
        &source,
        HistoryMessage::Journal {
            manifest: manifest.clone(),
            deletion_digest: digest.clone(),
            page: DeletionMessage::Fragment(fragment::fragment(&bytes, 0).unwrap()),
        },
    );
    reader.restart();
    assert!(reader
        .runtime
        .poll("journal-fragments")
        .unwrap()
        .messages
        .is_empty());
    for offset in (fragment::CHUNK..bytes.len()).step_by(fragment::CHUNK) {
        reader.deliver(
            "journal-fragments",
            &source,
            HistoryMessage::Journal {
                manifest: manifest.clone(),
                deletion_digest: digest.clone(),
                page: DeletionMessage::Fragment(fragment::fragment(&bytes, offset).unwrap()),
            },
        );
    }
    reader.deliver(
        "journal-fragments",
        &source,
        HistoryMessage::Page {
            manifest,
            total: 1,
            offset: 0,
            records: vec![record],
            fragment: None,
        },
    );
    let snapshot = reader.runtime.poll("journal-fragments").unwrap();
    assert_eq!(
        snapshot.history_sync.unwrap().state,
        HistorySyncState::Complete
    );
    assert_eq!(snapshot.messages.len(), 1);
    assert!(snapshot.messages[0].body.is_empty());
}
