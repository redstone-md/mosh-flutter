use super::*;

// Regression: Moss answering "no peers" used to count as a successful
// publish, so a message nobody could receive showed as Sent. A group has
// no acknowledgement and no resend loop, so the refusal has to land as a
// retryable failure the user can act on.
#[test]
fn no_peers_does_not_count_as_sent() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
    let mut groups = PrivateGroupRuntime::from_shared(runtime, temp_store(), None);
    let created = groups
        .create_group(CreateGroupRequest {
            label: Some("Empty Club".to_string()),
            display_name: "Alice".to_string(),
            listen_port: 42242,
            static_peer: None,
            org_pubkey: None,
        })
        .expect("group should be created");

    let _no_peers = no_peers_next_test_publish();
    let result = groups
        .send(&created.group_id, "nobody is here".to_string())
        .expect("send should return a result");

    assert_eq!(result.delivery_status, MessageDeliveryStatus::Failed);
    assert_eq!(
        result.delivery_error.as_deref(),
        Some("Moss error: no peers yet, so the message did not go out")
    );

    let live = groups.poll(&created.group_id).expect("poll should pass");
    let message = live
        .messages
        .iter()
        .find(|message| message.message_id.as_deref() == Some(result.message_id.as_str()))
        .expect("the message should be recorded");
    assert_eq!(message.delivery_status, Some(MessageDeliveryStatus::Failed));
    assert_eq!(message.retryable, Some(true));

    // The attempt record survived the failure, so the existing retry path
    // replays the same bytes without new machinery.
    let retried = groups
        .retry_message(&created.group_id, &result.message_id)
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
        "mosh-group-failed-send-{}.redb",
        std::process::id()
    ));
    let _ = std::fs::remove_file(&db_path);

    let persistence =
        Arc::new(Persistence::open_with_dek(&db_path, [21u8; 32]).expect("store should open"));
    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));

    let (group_id, message_id) = {
        let mut groups = PrivateGroupRuntime::from_shared(
            Arc::clone(&runtime),
            temp_store(),
            Some(persistence.clone()),
        );
        let created = groups
            .create_group(CreateGroupRequest {
                label: Some("Retry Club".to_string()),
                display_name: "Alice".to_string(),
                listen_port: 42241,
                static_peer: None,
                org_pubkey: None,
            })
            .expect("group should be created");
        let _publish_fail = fail_next_test_publish("simulated publish failure");
        let result = groups
            .send(&created.group_id, "hello failed group".to_string())
            .expect("send should return failed result");
        assert_eq!(result.delivery_status, MessageDeliveryStatus::Failed);
        assert_eq!(
            result.delivery_error.as_deref(),
            Some("Moss error: simulated publish failure")
        );

        let live = groups
            .poll(&created.group_id)
            .expect("poll should surface failed message");
        let failed = live
            .messages
            .iter()
            .find(|message| message.message_id.as_deref() == Some(result.message_id.as_str()))
            .expect("failed message should be recorded");
        assert_eq!(failed.delivery_status, Some(MessageDeliveryStatus::Failed));
        assert_eq!(failed.retryable, Some(true));

        (created.group_id, result.message_id)
    };

    let mut revived =
        PrivateGroupRuntime::from_shared(Arc::clone(&runtime), temp_store(), Some(persistence));
    revived.rehydrate();
    let listing = revived.list().expect("listing should pass");
    let group = listing
        .groups
        .iter()
        .find(|group| group.group_id == group_id)
        .expect("rehydrated group should be present");
    let failed = group
        .messages
        .iter()
        .find(|message| message.message_id.as_deref() == Some(message_id.as_str()))
        .expect("failed message should rehydrate");
    assert_eq!(failed.delivery_status, Some(MessageDeliveryStatus::Failed));
    assert_eq!(failed.retryable, Some(true));

    let _ = std::fs::remove_file(&db_path);
}

#[test]
fn retry_message_reuses_message_id_and_clears_failed_attempt() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut db_path: PathBuf = std::env::temp_dir();
    db_path.push(format!("mosh-group-retry-{}.redb", std::process::id()));
    let _ = std::fs::remove_file(&db_path);

    let persistence =
        Arc::new(Persistence::open_with_dek(&db_path, [22u8; 32]).expect("store should open"));
    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));

    let (group_id, failed_message_id) = {
        let mut groups = PrivateGroupRuntime::from_shared(
            Arc::clone(&runtime),
            temp_store(),
            Some(persistence.clone()),
        );
        let created = groups
            .create_group(CreateGroupRequest {
                label: Some("Retry Club".to_string()),
                display_name: "Alice".to_string(),
                listen_port: 42242,
                static_peer: None,
                org_pubkey: None,
            })
            .expect("group should be created");
        let _publish_fail = fail_next_test_publish("simulated publish failure");
        let failed = groups
            .send(&created.group_id, "retry this group message".to_string())
            .expect("failed send should still return a result");

        let retried = groups
            .retry_message(&created.group_id, &failed.message_id)
            .expect("retry should succeed");
        assert_eq!(retried.message_id, failed.message_id);
        assert_eq!(retried.delivery_status, MessageDeliveryStatus::Sent);

        let snapshot = groups.poll(&created.group_id).expect("poll should pass");
        let matching: Vec<&GroupMessage> = snapshot
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

        (created.group_id, failed.message_id)
    };

    let stored_attempt = persistence
        .get_outbound_attempt("private_group", &group_id, &failed_message_id)
        .expect("lookup should pass");
    assert!(stored_attempt.is_none());

    let _ = std::fs::remove_file(&db_path);
}

// Control frames used to be recorded in the replay set BEFORE verification
// and MLS processing, so a frame that failed (bad signature, undecryptable
// commit) could never be repaired by its own retransmission — the re-delivered
// bytes hashed to an already-seen key. The retransmission must now reach
// `handle_control`: the exemption is what repairs the session.
#[test]
fn a_failed_control_frame_is_retried_its_retransmission() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut view = MemberView::open(42397);

    // A commit whose MLS processing fails (garbage bytes are not a commit):
    // `handle_control` accepts the envelope and `apply_commit_sequenced`
    // fails, the transient shape a restart ("secret deleted for forward
    // secrecy") produces for real commits.
    let garbage_commit = serde_json::to_vec(&ControlEnvelope::Commit {
        group_id: view.group_id.clone(),
        from_fingerprint: view.cleo.fingerprint(),
        commit_b64: encode(b"not-a-real-commit"),
        roster_version: None,
    })
    .unwrap();
    let frame = MossReceivedMessage {
        channel: view.session().control_channel.clone(),
        payload: garbage_commit,
    };

    // First delivery: the frame fails MLS processing. Under the old
    // pre-recording it also filed itself as seen.
    {
        let session = view.runtime.groups.get_mut(&view.group_id).unwrap();
        assert!(
            session.handle_moss_message(frame.clone()).is_err(),
            "the garbage commit must fail MLS processing"
        );
    }

    // The retransmission of the SAME bytes — previously swallowed by the
    // replay set as a duplicate. It fails the same way (the bytes are still
    // garbage), which is the point: reaching handle_control again is the
    // repair path for the case where the first failure was transient (a
    // missing MLS secret after restart; the re-delivery carries the bytes
    // that DO process once the resync has landed).
    {
        let session = view.runtime.groups.get_mut(&view.group_id).unwrap();
        assert!(
            session.handle_moss_message(frame).is_err(),
            "the retransmission must reach handle_control and fail the same way — \
             being swallowed as a replay would mean a transient failure could \
             never be repaired"
        );
    }

    // The proof that the retransmission reached the MLS layer rather than
    // the dedup set: a member count unchanged by the garbage, and the
    // sequencer now holding a resync request (the gapped commit path), not
    // a swallowed frame.
    let session = view.runtime.groups.get(&view.group_id).unwrap();
    assert_eq!(
        session.crypto.member_count(),
        3,
        "garbage never admits anything"
    );
}
