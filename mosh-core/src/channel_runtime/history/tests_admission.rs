use super::tests::*;
use super::*;
use crate::moss_ffi::MOSS_TEST_LOCK;
use ed25519_dalek::SigningKey;

fn text(id: &str, body: &str) -> ChannelRecord {
    ChannelRecord {
        message_id: id.into(),
        sent_at_ms: 1000,
        from_device: "Unverified label".into(),
        from_fingerprint: "22".repeat(32),
        content: records::Content::Text(body.into()),
        origin: None,
        legacy_id_absent: false,
    }
}
fn page(fixture: &mut Fixture, room: &str, source: &SigningKey, rows: Vec<ChannelRecord>) {
    let total = rows.len();
    fixture.deliver(
        room,
        source,
        HistoryMessage::Page {
            manifest: fixture.manifest(room),
            total,
            offset: 0,
            records: rows,
            fragment: None,
        },
    );
}

#[test]
fn refused_import_retries_without_advancing_or_authenticating_legacy_rows() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut f = Fixture::new();
    let source = SigningKey::from_bytes(&[19; 32]);
    f.join("refused-history");
    f.offer_rows(
        "refused-history",
        &source,
        &[text("legacy-1", "unsigned original")],
    );
    f.journal("refused-history", &source);
    let fault = f.store.refuse_message_writes(CHANNEL_HISTORY);
    page(
        &mut f,
        "refused-history",
        &source,
        vec![text("legacy-1", "unsigned original")],
    );
    let failed = f.runtime.poll("refused-history").unwrap();
    assert!(failed.messages.is_empty());
    assert_eq!(
        failed.history_sync.unwrap().reason,
        Some(HistorySyncReason::StorageRefused)
    );
    drop(fault);
    page(
        &mut f,
        "refused-history",
        &source,
        vec![text("legacy-1", "unsigned original")],
    );
    let restored = f.runtime.poll("refused-history").unwrap();
    assert_eq!(restored.messages.len(), 1);
    assert_eq!(restored.messages[0].body, "unsigned original");
    assert!(restored.messages[0]
        .metadata
        .as_ref()
        .is_none_or(|m| m.origin.is_none() && !m.can_delete_for_everyone));
    assert_eq!(
        restored.history_sync.unwrap().state,
        HistorySyncState::Complete
    );
}

#[test]
fn an_invalid_original_signature_cannot_hide_behind_the_holder_signature() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut f = Fixture::new();
    let holder = SigningKey::from_bytes(&[20; 32]);
    let author = SigningKey::from_bytes(&[21; 32]);
    f.join("original-proof");
    let mut record = text("original-1", "original");
    record.from_fingerprint = hex::encode(author.verifying_key().as_bytes());
    record.origin = Some(
        crate::message_deletion::MessageOrigin::sign(
            "channel:original-proof",
            "original-1",
            b"original",
            &author,
            None,
        )
        .unwrap(),
    );
    f.offer_rows(
        "original-proof",
        &holder,
        &[text("other", "valid legacy"), record.clone()],
    );
    f.journal("original-proof", &holder);
    let mut forged = record.clone();
    forged.content = records::Content::Text("forged".into());
    page(
        &mut f,
        "original-proof",
        &holder,
        vec![text("other", "valid legacy"), forged],
    );
    assert!(f
        .runtime
        .poll("original-proof")
        .unwrap()
        .messages
        .is_empty());
    page(
        &mut f,
        "original-proof",
        &holder,
        vec![text("other", "valid legacy"), record.clone()],
    );
    let restored = f.runtime.poll("original-proof").unwrap();
    assert_eq!(restored.messages.len(), 2);
    assert_eq!(
        restored.messages[1].metadata.as_ref().unwrap().origin,
        record.origin
    );
}

#[test]
fn changing_source_restarts_the_manifest_and_rejects_conflicting_native_ids_atomically() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut f = Fixture::new();
    let first = SigningKey::from_bytes(&[22; 32]);
    let second = SigningKey::from_bytes(&[23; 32]);
    f.join("source-change");
    f.offer_rows("source-change", &first, &[text("same-id", "original")]);
    f.journal("source-change", &first);
    page(
        &mut f,
        "source-change",
        &first,
        vec![text("same-id", "original")],
    );
    f.offer_rows(
        "source-change",
        &second,
        &[text("same-id", "original"), text("new-id", "new")],
    );
    f.journal("source-change", &second);
    page(
        &mut f,
        "source-change",
        &second,
        vec![text("same-id", "conflict"), text("new-id", "new")],
    );
    assert_eq!(f.runtime.poll("source-change").unwrap().messages.len(), 1);
    page(
        &mut f,
        "source-change",
        &second,
        vec![text("same-id", "original"), text("new-id", "new")],
    );
    let snapshot = f.runtime.poll("source-change").unwrap();
    assert_eq!(snapshot.messages.len(), 2);
    assert_eq!(snapshot.messages[0].body, "original");
    assert_eq!(
        snapshot.history_sync.unwrap().state,
        HistorySyncState::Complete
    );
}

#[test]
fn personal_tombstones_win_over_a_later_holder_copy() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut f = Fixture::new();
    let first = SigningKey::from_bytes(&[24; 32]);
    let second = SigningKey::from_bytes(&[25; 32]);
    f.join("erased-history");
    f.offer_rows(
        "erased-history",
        &first,
        &[text("erased-1", "private erasure")],
    );
    f.journal("erased-history", &first);
    page(
        &mut f,
        "erased-history",
        &first,
        vec![text("erased-1", "private erasure")],
    );
    f.runtime
        .delete_messages(
            "erased-history",
            &["erased-1".into()],
            crate::message_deletion::DeleteScope::ForMe,
        )
        .unwrap();
    f.offer_rows(
        "erased-history",
        &second,
        &[text("erased-1", "private erasure")],
    );
    f.journal("erased-history", &second);
    page(
        &mut f,
        "erased-history",
        &second,
        vec![text("erased-1", "private erasure")],
    );
    let snapshot = f.runtime.poll("erased-history").unwrap();
    assert!(snapshot.messages.is_empty());
    assert_eq!(
        snapshot.history_sync.unwrap().state,
        HistorySyncState::Complete
    );
}

#[test]
fn another_holder_cannot_replace_the_first_unproved_receive_time_or_label() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut f = Fixture::new();
    let (first, second, author) = (
        SigningKey::from_bytes(&[31; 32]),
        SigningKey::from_bytes(&[32; 32]),
        SigningKey::from_bytes(&[33; 32]),
    );
    for signed in [false, true] {
        let room = if signed {
            "original-time"
        } else {
            "legacy-time"
        };
        f.join(room);
        let mut record = text(&format!("legacy-{}", "a".repeat(64)), "same occurrence");
        record.legacy_id_absent = !signed;
        if signed {
            record.from_fingerprint = hex::encode(author.verifying_key().as_bytes());
            record.origin = Some(
                crate::message_deletion::MessageOrigin::sign(
                    &format!("channel:{room}"),
                    &record.message_id,
                    b"same occurrence",
                    &author,
                    None,
                )
                .unwrap(),
            );
        }
        f.offer_rows(room, &first, std::slice::from_ref(&record));
        f.journal(room, &first);
        page(&mut f, room, &first, vec![record.clone()]);
        record.sent_at_ms = 9999;
        if signed {
            record.from_device = "Another holder's label".into();
        }
        f.offer_rows(room, &second, std::slice::from_ref(&record));
        f.journal(room, &second);
        page(&mut f, room, &second, vec![record]);
        f.restart();
        let snapshot = f.runtime.poll(room).unwrap();
        assert_eq!(snapshot.messages.len(), 1);
        assert_eq!(snapshot.messages[0].sent_at_ms, Some(1000));
        assert_eq!(snapshot.messages[0].from_device, "Unverified label");
        assert_eq!(
            snapshot.history_sync.unwrap().state,
            HistorySyncState::Complete
        );
    }
}

#[test]
fn leaving_and_rejoining_starts_a_fresh_recovery_instead_of_restoring_a_deleted_cursor() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut f = Fixture::new();
    let source = SigningKey::from_bytes(&[34; 32]);
    f.join("rejoin-history");
    let record = text("retained", "available from holder");
    f.offer_rows("rejoin-history", &source, std::slice::from_ref(&record));
    f.journal("rejoin-history", &source);
    page(&mut f, "rejoin-history", &source, vec![record.clone()]);
    f.runtime.leave("rejoin-history").unwrap();
    f.join("rejoin-history");
    assert_eq!(
        f.runtime
            .poll("rejoin-history")
            .unwrap()
            .history_sync
            .unwrap()
            .state,
        HistorySyncState::WaitingForSource,
    );
    f.offer_rows("rejoin-history", &source, std::slice::from_ref(&record));
    f.journal("rejoin-history", &source);
    page(&mut f, "rejoin-history", &source, vec![record]);
    assert_eq!(f.runtime.poll("rejoin-history").unwrap().messages.len(), 1);
}
