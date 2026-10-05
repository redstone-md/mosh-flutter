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

#[test]
fn a_personal_alias_erases_metadata_free_replay_in_every_history_table() {
    use crate::conversation::test_message::TestMessage;
    let temp = crate::test_temp_directory::TempDirectory::new("deletion-legacy-replay");
    let store = Persistence::open_with_dek(&temp.path().join("history"), [39; 32]).unwrap();
    for (kind, tables) in [
        ("dm", DM_HISTORY),
        ("group", GROUP_HISTORY),
        ("channel", CHANNEL_HISTORY),
    ] {
        let context = format!("{kind}:chat");
        let message = TestMessage::new("author", "secret")
            .with_id("message")
            .at(1);
        let alias = crate::message_deletion::correlation::text_key(&context, &message).unwrap();
        let record = personal_record(context, alias);
        store.save_account_deletions("local", &[record]).unwrap();
        let row = serde_json::json!({"conversation_id": "chat", "message_id": "message",
            "sent_at_ms": 1, "message": {"message_id": "message", "sent_at_ms": 1,
            "body": "secret", "metadata": null, "from_fingerprint": "author",
            "from_device": if kind == "dm" { "author" } else { "Display label" }}});
        store
            .append_history_message(
                tables,
                "chat",
                1,
                "message",
                &serde_json::to_vec(&row).unwrap(),
            )
            .unwrap();
        let saved: serde_json::Value =
            serde_json::from_slice(&store.list_history_messages(tables, "chat").unwrap()[0])
                .unwrap();
        assert_eq!(saved.pointer("/message/body").unwrap(), "", "{kind}");
        assert_eq!(
            saved.pointer("/message/metadata/deletion/scope").unwrap(),
            "ForMe"
        );
    }
}

fn personal_record(
    context: String,
    alias: Option<String>,
) -> crate::message_deletion::DeletionRecord {
    use crate::message_deletion::{DeleteScope, DeletionRecord, DeletionStatus};
    DeletionRecord {
        context,
        key: "a".repeat(64),
        personal_correlation: alias,
        scope: DeleteScope::ForMe,
        owner: "local".into(),
        local_only: false,
        status: DeletionStatus::Confirmed,
        administrator: None,
        request: None,
        acknowledgement: None,
    }
}
