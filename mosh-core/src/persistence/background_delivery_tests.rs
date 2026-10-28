use super::*;
use crate::test_temp_directory::TempDirectory;
use std::sync::Arc;

fn append(store: &Persistence, id: &str, text: &str) -> Result<(), PersistenceError> {
    let admission = BackgroundMessageAdmission {
        tables: DM_HISTORY,
        conversation_id: "dm-original".into(),
        occurrence_id: format!("author/{id}"),
        message_id: id.into(),
        sent_at_ms: 100,
    };
    let row = serde_json::to_vec(&serde_json::json!({
        "conversation_id":"dm-original", "sent_at_ms":100, "message_id":id,
        "message":{"body":text,"from_device":"Remote sender","metadata":{"is_own":false}}
    }))
    .unwrap();
    store.append_history_message_with_background(
        DM_HISTORY,
        "dm-original",
        100,
        id,
        &row,
        Some(&admission),
    )
}

#[test]
fn duplicate_and_stale_ack_never_erase_a_newer_pending_revision() {
    let directory = TempDirectory::new("background-exact-ack");
    let path = directory.path().join("history.redb");
    let store = Persistence::open_with_dek(&path, [31; 32]).unwrap();
    store.save_background_intent(false, true).unwrap();
    append(&store, "first", "first text").unwrap();
    let first = store
        .pending_background_notifications(16)
        .unwrap()
        .remove(0);
    append(&store, "first", "first text").unwrap();
    assert_eq!(
        store.pending_background_notifications(16).unwrap()[0].revision,
        first.revision
    );
    append(&store, "second", "second text").unwrap();
    store
        .ack_background_notification(&first.id, first.revision)
        .unwrap();
    let second = store
        .pending_background_notifications(16)
        .unwrap()
        .remove(0);
    assert_eq!(second.id, first.id);
    assert_eq!(second.message_count, 2);
    assert!(second.revision > first.revision);
    assert_eq!(second.text.as_deref(), Some("second text"));
    assert!(store
        .pending_background_notifications(0)
        .unwrap()
        .is_empty());
    drop(store);
    let store = Persistence::open_with_dek(&path, [31; 32]).unwrap();
    assert_eq!(
        store.pending_background_notifications(16).unwrap()[0].revision,
        second.revision
    );
    store
        .ack_background_notification("other-notification", second.revision)
        .unwrap();
    assert_eq!(store.pending_background_notifications(16).unwrap().len(), 1);
    store
        .ack_background_notification(&second.id, second.revision)
        .unwrap();
    assert!(store
        .pending_background_notifications(16)
        .unwrap()
        .is_empty());
}

#[test]
fn refused_history_transaction_accepts_neither_notification_nor_watermark() {
    let directory = TempDirectory::new("background-atomic-admission");
    let store = Arc::new(
        Persistence::open_with_dek(&directory.path().join("history.redb"), [32; 32]).unwrap(),
    );
    store.save_background_intent(false, true).unwrap();
    let fault = store.refuse_message_writes(DM_HISTORY);
    assert!(append(&store, "refused", "must retry").is_err());
    assert!(store
        .pending_background_notifications(16)
        .unwrap()
        .is_empty());
    drop(fault);
    append(&store, "refused", "must retry").unwrap();
    let pending = store.pending_background_notifications(16).unwrap();
    assert_eq!(pending.len(), 1);
    assert_eq!(pending[0].revision, 1);
}

#[test]
fn upgrade_history_and_a_later_tombstone_never_publish_old_or_erased_content() {
    let directory = TempDirectory::new("background-upgrade-baseline");
    let store =
        Persistence::open_with_dek(&directory.path().join("history.redb"), [33; 32]).unwrap();
    append(&store, "old", "old history").unwrap();
    store.save_background_intent(false, true).unwrap();
    append(&store, "old", "old history").unwrap();
    assert!(store
        .pending_background_notifications(16)
        .unwrap()
        .is_empty());
    append(&store, "new", "erase before publication").unwrap();
    let tombstone = serde_json::to_vec(&serde_json::json!({
        "conversation_id":"dm-original", "sent_at_ms":100, "message_id":"new",
        "message":{"body":"","metadata":{"is_own":false,"deletion":{"scope":"ForMe","status":"Confirmed","administrator":null}}}
    })).unwrap();
    store
        .append_history_message(DM_HISTORY, "dm-original", 100, "new", &tombstone)
        .unwrap();
    assert!(store
        .pending_background_notifications(16)
        .unwrap()
        .is_empty());
}
