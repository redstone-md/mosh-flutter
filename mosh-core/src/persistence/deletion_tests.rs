use super::*;

#[test]
fn cached_file_references_compare_the_actual_sanitized_path() {
    let temp = crate::test_temp_directory::TempDirectory::new("deletion-references");
    let store = Persistence::open_with_dek(&temp.path().join("history"), [39; 32]).unwrap();
    let hash = "a".repeat(64);
    let row = serde_json::json!({"message": {"attachment": {
        "content_hash": hash, "file_name": "name/file.bin"
    }}});
    store
        .append_message("closed-chat", 1, "file", &serde_json::to_vec(&row).unwrap())
        .unwrap();
    assert!(store.attachment_referenced(&hash, "name_file.bin").unwrap());
    assert!(!store.attachment_referenced(&hash, "other.bin").unwrap());
}

#[test]
fn late_outbox_writes_do_not_restore_cancelled_sends() {
    use crate::message_deletion::DeleteScope;
    let temp = crate::test_temp_directory::TempDirectory::new("deletion-outbox");
    let store = Persistence::open_with_dek(&temp.path().join("history"), [39; 32]).unwrap();
    for (id, scope, published, retained) in [
        ("shared", DeleteScope::ForEveryone, true, false),
        ("unsent", DeleteScope::ForMe, false, false),
        ("sent", DeleteScope::ForMe, true, true),
    ] {
        let row = serde_json::json!({"conversation_id": "chat", "message_id": id,
        "sent_at_ms": 1, "message": {"body": "", "metadata": {"deletion": {
            "scope": scope, "status": "Confirmed", "administrator": null
        }}}});
        store
            .append_message("chat", 1, id, &serde_json::to_vec(&row).unwrap())
            .unwrap();
        let original =
            serde_json::to_vec(&serde_json::json!({"message": {"body": "secret"}})).unwrap();
        let attempt =
            serde_json::to_vec(&serde_json::json!({"sent_at_ms": 1, "ever_published": published}))
                .unwrap();
        store
            .commit_send(DM_HISTORY, "chat", 1, id, &original, Some(&attempt))
            .unwrap();
        assert_eq!(
            store
                .get_outbound_attempt("private_dm", "chat", id)
                .unwrap()
                .is_some(),
            retained
        );
        store
            .put_outbound_attempt("private_dm", "chat", id, &attempt)
            .unwrap();
        assert_eq!(
            store
                .get_outbound_attempt("private_dm", "chat", id)
                .unwrap()
                .is_some(),
            retained
        );
        let saved: serde_json::Value = serde_json::from_slice(
            &store
                .get(MESSAGES, &Persistence::history_message_key("chat", 1, id))
                .unwrap()
                .unwrap(),
        )
        .unwrap();
        assert_eq!(saved.pointer("/message/body").unwrap(), "");
    }
}
