//! The channel runtime tests.
use super::*;
use crate::conversation::history::StoredMessage;
use crate::moss_ffi::{
    drain_received_messages, fail_next_test_publish, no_peers_next_test_publish, MossFfiRuntime,
    MOSS_TEST_LOCK,
};
use crate::persistence::Persistence;
use std::path::PathBuf;

fn temp_store() -> Arc<AttachmentStore> {
    let mut path = std::env::temp_dir();
    path.push(format!(
        "mosh-channel-attachments-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    Arc::new(AttachmentStore::new(&path).expect("attachment store should init"))
}

#[test]
fn normalize_strips_prefix_and_lowercases() {
    assert_eq!(normalize_name("@MOSH-DEV").unwrap(), "mosh-dev");
    assert_eq!(normalize_name("#general_chat").unwrap(), "general_chat");
    assert_eq!(normalize_name("  spaced  ").unwrap(), "spaced");
}

#[test]
fn normalize_rejects_invalid_input() {
    assert!(normalize_name("").is_err());
    assert!(normalize_name("with spaces").is_err());
    assert!(normalize_name("emoji😀").is_err());
    assert!(normalize_name(&"a".repeat(MAX_NAME_LEN + 1)).is_err());
}

#[test]
fn channel_name_strips_topic_prefix() {
    assert_eq!(
        channel_name_from_topic("public-channel/mosh-dev"),
        Some("mosh-dev")
    );
    assert_eq!(channel_name_from_topic("mls-control/sid"), None);
}

// Every joined channel now shares one moss node, so a channel's own room is
// what separates it from the others — and the node outliving the channel is
// a new failure mode: nothing ends its subscriptions unless leave says so.
#[test]
fn channels_share_one_node_and_leave_releases_it() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
    let mut channels = ChannelRuntime::from_shared(runtime, temp_store(), None);
    for (name, port) in [("shared-one", 42360u16), ("shared-two", 42361)] {
        channels
            .join(JoinChannelRequest {
                name: name.to_string(),
                display_name: "Alice".to_string(),
                listen_port: port,
                static_peer: None,
            })
            .unwrap_or_else(|error| panic!("{name} should join: {error}"));
    }

    // One node, not two. Two would present the same peer id from two ports
    // and a remote peer would keep only the first.
    let one = channels.channels.get("shared-one").expect("first channel");
    let two = channels.channels.get("shared-two").expect("second channel");
    assert_eq!(
        Arc::as_ptr(&one.node),
        Arc::as_ptr(&two.node),
        "two joined channels started two moss nodes under one identity"
    );
    assert_ne!(
        one.mesh_id, two.mesh_id,
        "channels must stay in separate rooms on the shared node"
    );

    channels.leave("shared-one").expect("first should leave");
    assert!(
        channels.shared_node.current().is_some(),
        "the shared node went down while a channel was still joined"
    );
    channels.leave("shared-two").expect("second should leave");
    assert!(
        channels.shared_node.current().is_none(),
        "the shared node outlived every channel — nothing would ever stop moss"
    );
}

#[test]
fn channel_history_survives_restart_without_duplicate_tail() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut db_path: PathBuf = std::env::temp_dir();
    db_path.push(format!(
        "mosh-channel-rehydrate-{}.redb",
        std::process::id()
    ));
    let _ = std::fs::remove_file(&db_path);

    let persistence =
        Arc::new(Persistence::open_with_dek(&db_path, [16u8; 32]).expect("store should open"));
    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));

    {
        let mut channels = ChannelRuntime::from_shared(
            Arc::clone(&runtime),
            temp_store(),
            Some(persistence.clone()),
        );
        channels
            .join(JoinChannelRequest {
                name: "restart-channel".to_string(),
                display_name: "Alice".to_string(),
                listen_port: 42340,
                static_peer: None,
            })
            .expect("channel should join");
        channels
            .send("restart-channel", "hello after channel restart".to_string())
            .expect("channel message should send");
    }

    let mut revived = ChannelRuntime::from_shared(
        Arc::clone(&runtime),
        temp_store(),
        Some(persistence.clone()),
    );
    revived.rehydrate();

    let listing = revived.list().expect("listing should pass");
    let channel = listing
        .channels
        .iter()
        .find(|channel| channel.name == "restart-channel")
        .expect("rehydrated channel should be present");
    assert!(
        channel
            .messages
            .iter()
            .any(|message| message.body == "hello after channel restart"),
        "rehydrated channel message missing: {:?}",
        channel.messages
    );

    let listing2 = revived.list().expect("second listing should pass");
    let channel2 = listing2
        .channels
        .iter()
        .find(|channel| channel.name == "restart-channel")
        .expect("channel should still be present");
    let matching = channel2
        .messages
        .iter()
        .filter(|message| message.body == "hello after channel restart")
        .count();
    assert_eq!(matching, 1, "persist tail duplicated the channel message");

    let _ = std::fs::remove_file(&db_path);
}

// Regression: Moss answering "no peers" used to count as a successful
// publish, so a message nobody could receive showed as Sent. A channel has
// no acknowledgement and no resend loop, so the refusal has to land as a
// retryable failure the user can act on.
#[test]
fn no_peers_does_not_count_as_sent() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
    let mut channels = ChannelRuntime::from_shared(runtime, temp_store(), None);
    channels
        .join(JoinChannelRequest {
            name: "empty-channel".to_string(),
            display_name: "Alice".to_string(),
            listen_port: 42343,
            static_peer: None,
        })
        .expect("channel should join");

    let _no_peers = no_peers_next_test_publish();
    let result = channels
        .send("empty-channel", "nobody is here".to_string())
        .expect("send should return a result");

    assert_eq!(result.delivery_status, MessageDeliveryStatus::Failed);
    assert_eq!(
        result.delivery_error.as_deref(),
        Some("Moss error: no peers yet, so the message did not go out")
    );

    let live = channels.poll("empty-channel").expect("poll should pass");
    let message = live
        .messages
        .iter()
        .find(|message| message.message_id.as_deref() == Some(result.message_id.as_str()))
        .expect("the message should be recorded");
    assert_eq!(message.delivery_status, Some(MessageDeliveryStatus::Failed));
    assert_eq!(message.retryable, Some(true));

    // The attempt record survived the failure, so the existing retry path
    // replays the same bytes without new machinery.
    let retried = channels
        .retry_message("empty-channel", &result.message_id)
        .expect("retry should succeed once a peer is there");
    assert_eq!(retried.delivery_status, MessageDeliveryStatus::Sent);
}

#[test]
fn failed_send_rehydrates_as_retryable_message() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut db_path: PathBuf = std::env::temp_dir();
    db_path.push(format!(
        "mosh-channel-failed-send-{}.redb",
        std::process::id()
    ));
    let _ = std::fs::remove_file(&db_path);

    let persistence =
        Arc::new(Persistence::open_with_dek(&db_path, [17u8; 32]).expect("store should open"));
    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));

    let message_id = {
        let mut channels = ChannelRuntime::from_shared(
            Arc::clone(&runtime),
            temp_store(),
            Some(persistence.clone()),
        );
        channels
            .join(JoinChannelRequest {
                name: "retry-channel".to_string(),
                display_name: "Alice".to_string(),
                listen_port: 42341,
                static_peer: None,
            })
            .expect("channel should join");
        let _publish_fail = fail_next_test_publish("simulated publish failure");
        let result = channels
            .send("retry-channel", "hello failed channel".to_string())
            .expect("send should return failed result");
        assert_eq!(result.delivery_status, MessageDeliveryStatus::Failed);
        assert_eq!(
            result.delivery_error.as_deref(),
            Some("Moss error: simulated publish failure")
        );

        let live = channels
            .poll("retry-channel")
            .expect("poll should surface failed message");
        let failed = live
            .messages
            .iter()
            .find(|message| message.message_id.as_deref() == Some(result.message_id.as_str()))
            .expect("failed message should be recorded");
        assert_eq!(failed.delivery_status, Some(MessageDeliveryStatus::Failed));
        assert_eq!(failed.retryable, Some(true));

        result.message_id
    };

    let mut revived =
        ChannelRuntime::from_shared(Arc::clone(&runtime), temp_store(), Some(persistence));
    revived.rehydrate();
    let listing = revived.list().expect("listing should pass");
    let channel = listing
        .channels
        .iter()
        .find(|channel| channel.name == "retry-channel")
        .expect("rehydrated channel should be present");
    let failed = channel
        .messages
        .iter()
        .find(|message| message.message_id.as_deref() == Some(message_id.as_str()))
        .expect("failed message should rehydrate");
    assert_eq!(failed.delivery_status, Some(MessageDeliveryStatus::Failed));
    assert_eq!(failed.retryable, Some(true));

    let _ = std::fs::remove_file(&db_path);
}

// Regression, end to end: a send whose message row reached disk while its
// attempt row did not used to rehydrate as a Pending message nothing would
// ever settle — a spinner the user could not even retry away. The rule
// itself is proved once in `conversation::history`; this checks it reaches
// the snapshot the app renders.
#[test]
fn a_torn_send_row_rehydrates_as_a_plain_failure() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut db_path: PathBuf = std::env::temp_dir();
    db_path.push(format!(
        "mosh-channel-torn-send-{}.redb",
        std::process::id()
    ));
    let _ = std::fs::remove_file(&db_path);

    let persistence =
        Arc::new(Persistence::open_with_dek(&db_path, [19u8; 32]).expect("store should open"));
    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));

    {
        let mut channels = ChannelRuntime::from_shared(
            Arc::clone(&runtime),
            temp_store(),
            Some(persistence.clone()),
        );
        channels
            .join(JoinChannelRequest {
                name: "torn-channel".to_string(),
                display_name: "Alice".to_string(),
                listen_port: 42345,
                static_peer: None,
            })
            .expect("channel should join");
    }

    // What a crash between the two writes leaves behind: the message row
    // down as Pending, its attempt row never written.
    let stored = StoredMessage {
        conversation_id: "torn-channel".to_string(),
        sent_at_ms: 100,
        message_id: "torn-1".to_string(),
        message: ChannelMessage {
            from_device: "Alice".to_string(),
            from_fingerprint: "alice-fingerprint".to_string(),
            body: "cut off mid-send".to_string(),
            message_id: Some("torn-1".to_string()),
            sent_at_ms: Some(100),
            attachment: None,
            delivery_status: Some(MessageDeliveryStatus::Pending),
            delivery_error: None,
            retryable: None,
            retry_count: Some(0),
        },
    };
    persistence
        .append_history_message(
            CHANNEL_HISTORY,
            "torn-channel",
            100,
            "torn-1",
            &serde_json::to_vec(&stored).expect("stored message json"),
        )
        .expect("message row should write");

    let mut revived =
        ChannelRuntime::from_shared(Arc::clone(&runtime), temp_store(), Some(persistence));
    revived.rehydrate();
    let listing = revived.list().expect("listing should pass");
    let channel = listing
        .channels
        .iter()
        .find(|channel| channel.name == "torn-channel")
        .expect("rehydrated channel should be present");
    let torn = channel
        .messages
        .iter()
        .find(|message| message.message_id.as_deref() == Some("torn-1"))
        .expect("the torn message should rehydrate");

    assert_eq!(torn.delivery_status, Some(MessageDeliveryStatus::Failed));
    // No attempt record means no payload, so there is nothing to retry
    // with — and the runtime says so if the user tries anyway.
    assert_eq!(torn.retryable, Some(false));
    assert!(matches!(
        revived.retry_message("torn-channel", "torn-1"),
        Err(ChannelRuntimeError::MissingMessage(_))
    ));

    let _ = std::fs::remove_file(&db_path);
}

#[test]
fn retry_message_reuses_message_id_and_clears_failed_attempt() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut db_path: PathBuf = std::env::temp_dir();
    db_path.push(format!("mosh-channel-retry-{}.redb", std::process::id()));
    let _ = std::fs::remove_file(&db_path);

    let persistence =
        Arc::new(Persistence::open_with_dek(&db_path, [18u8; 32]).expect("store should open"));
    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));

    let failed_message_id = {
        let mut channels = ChannelRuntime::from_shared(
            Arc::clone(&runtime),
            temp_store(),
            Some(persistence.clone()),
        );
        channels
            .join(JoinChannelRequest {
                name: "retry-channel".to_string(),
                display_name: "Alice".to_string(),
                listen_port: 42342,
                static_peer: None,
            })
            .expect("channel should join");
        let _publish_fail = fail_next_test_publish("simulated publish failure");
        let failed = channels
            .send("retry-channel", "retry this channel message".to_string())
            .expect("failed send should still return a result");

        let retried = channels
            .retry_message("retry-channel", &failed.message_id)
            .expect("retry should succeed");
        assert_eq!(retried.message_id, failed.message_id);
        assert_eq!(retried.delivery_status, MessageDeliveryStatus::Sent);

        let snapshot = channels.poll("retry-channel").expect("poll should pass");
        let matching: Vec<&ChannelMessage> = snapshot
            .messages
            .iter()
            .filter(|message| message.message_id.as_deref() == Some(failed.message_id.as_str()))
            .collect();
        assert_eq!(
            matching.len(),
            1,
            "retry should update, not duplicate, the row"
        );
        assert_eq!(
            matching[0].delivery_status,
            Some(MessageDeliveryStatus::Sent)
        );
        assert_eq!(matching[0].retry_count, Some(1));

        failed.message_id
    };

    let stored_attempt = persistence
        .get_outbound_attempt("channel", "retry-channel", &failed_message_id)
        .expect("lookup should pass");
    assert!(stored_attempt.is_none());

    let _ = std::fs::remove_file(&db_path);
}
