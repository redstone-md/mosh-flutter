use super::{tests::*, *};
use crate::moss_ffi::MOSS_TEST_LOCK;
use ed25519_dalek::SigningKey;

#[test]
fn recovered_incoming_alerts_are_atomic_and_exclude_unsigned_own_and_repeated_rows() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut f = Fixture::new();
    f.join("background-history");
    f.store.save_background_intent(false, true).unwrap();
    let source = SigningKey::from_bytes(&[9; 32]);
    let author = SigningKey::from_bytes(&[10; 32]);
    let own = f
        .runtime
        .channels
        .get("background-history")
        .unwrap()
        .node
        .identity_signer()
        .unwrap()
        .clone();
    let rows = vec![
        record("unsigned", None),
        record("own", Some(&own)),
        record("incoming", Some(&author)),
    ];
    f.offer_rows("background-history", &source, &rows);
    f.journal("background-history", &source);
    let fault = f.store.refuse_message_writes(CHANNEL_HISTORY);
    f.deliver(
        "background-history",
        &source,
        HistoryMessage::Page {
            manifest: f.manifest("background-history"),
            total: 3,
            offset: 0,
            records: rows.clone(),
            fragment: None,
        },
    );
    assert!(f
        .store
        .pending_background_notifications(16)
        .unwrap()
        .is_empty());
    assert!(f
        .runtime
        .poll("background-history")
        .unwrap()
        .messages
        .is_empty());
    drop(fault);
    f.deliver(
        "background-history",
        &source,
        HistoryMessage::Page {
            manifest: f.manifest("background-history"),
            total: 3,
            offset: 0,
            records: rows.clone(),
            fragment: None,
        },
    );
    let first = f
        .store
        .pending_background_notifications(16)
        .unwrap()
        .remove(0);
    assert_eq!(first.message_count, 1);
    assert_eq!(first.text.as_deref(), Some("incoming"));
    let another = SigningKey::from_bytes(&[11; 32]);
    f.offer_rows("background-history", &another, &rows);
    f.journal("background-history", &another);
    f.deliver(
        "background-history",
        &another,
        HistoryMessage::Page {
            manifest: f.manifest("background-history"),
            total: 3,
            offset: 0,
            records: rows,
            fragment: None,
        },
    );
    assert_eq!(
        f.store.pending_background_notifications(16).unwrap()[0].revision,
        first.revision
    );
    f.runtime
        .delete_messages(
            "background-history",
            &["incoming".into()],
            crate::message_deletion::DeleteScope::ForMe,
        )
        .unwrap();
    assert!(f
        .store
        .pending_background_notifications(16)
        .unwrap()
        .is_empty());
}

fn record(id: &str, author: Option<&SigningKey>) -> ChannelRecord {
    ChannelRecord {
        message_id: id.into(),
        sent_at_ms: 1000,
        from_device: "Unproved label".into(),
        from_fingerprint: author
            .map(|key| hex::encode(key.verifying_key().as_bytes()))
            .unwrap_or_else(|| "22".repeat(32)),
        content: records::Content::Text(id.into()),
        legacy_id_absent: false,
        origin: author.map(|key| {
            crate::message_deletion::MessageOrigin::sign(
                "channel:background-history",
                id,
                id.as_bytes(),
                key,
                None,
            )
            .unwrap()
        }),
    }
}

// The limit is in characters on both ends: a channel text of 4096 emoji
// (16 KiB) that a peer may send must also be a valid history record.
#[test]
fn history_accepts_a_text_at_the_character_limit() {
    let at_limit = "😀".repeat(crate::conversation::MAX_TEXT_CHARS);
    let mut fits = record("limit", None);
    fits.content = records::Content::Text(at_limit.clone());
    assert!(fits.validate("channel:background-history").is_ok());
    let mut over = record("limit", None);
    over.content = records::Content::Text(at_limit + "😀");
    assert!(over.validate("channel:background-history").is_err());
}
