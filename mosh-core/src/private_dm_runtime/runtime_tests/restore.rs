use super::*;

#[test]
fn waiting_creator_invite_survives_restart() {
    use crate::persistence::Persistence;
    use std::path::PathBuf;

    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut db_path: PathBuf = std::env::temp_dir();
    db_path.push(format!(
        "mosh-dm-waiting-invite-{}.redb",
        std::process::id()
    ));
    let _ = std::fs::remove_file(&db_path);

    let persistence =
        Arc::new(Persistence::open_with_dek(&db_path, [29u8; 32]).expect("store should open"));
    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));

    let (session_id, invite_uri) = {
        let mut alice = PrivateDmRuntime::from_shared(
            Arc::clone(&runtime),
            temp_store(),
            Some(persistence.clone()),
        );
        let invite = alice
            .create_invite(StartSessionRequest {
                display_name: "Alice".to_string(),
                listen_port: 42170,
                static_peer: None,
            })
            .expect("Alice invite should be created");
        (invite.session_id, invite.invite_uri)
    };

    let mut revived =
        PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), Some(persistence));
    revived.rehydrate();

    let listing = revived.list_sessions().expect("listing should pass");
    let session = listing
        .sessions
        .iter()
        .find(|session| session.session_id == session_id)
        .expect("waiting invite should rehydrate");

    assert_eq!(session.state, DmSessionState::Pending);
    assert_eq!(session.role, "alice");
    assert_eq!(session.invite_uri.as_deref(), Some(invite_uri.as_str()));
    assert!(session.messages.is_empty());

    let _ = std::fs::remove_file(&db_path);
}

#[test]
fn restored_inbound_history_waits_for_live_peer() {
    use crate::persistence::Persistence;
    use std::path::PathBuf;

    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut db_path: PathBuf = std::env::temp_dir();
    db_path.push(format!("mosh-dm-inbound-ready-{}.redb", std::process::id()));
    let _ = std::fs::remove_file(&db_path);

    let persistence =
        Arc::new(Persistence::open_with_dek(&db_path, [31u8; 32]).expect("store should open"));
    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));

    let session_id = {
        let mut alice = PrivateDmRuntime::from_shared(
            Arc::clone(&runtime),
            temp_store(),
            Some(persistence.clone()),
        );
        let invite = alice
            .create_invite(StartSessionRequest {
                display_name: "Alice".to_string(),
                listen_port: 42171,
                static_peer: None,
            })
            .expect("Alice invite should be created");
        let message_id = "inbound-000001";
        let sent_at_ms = 1;
        let message = ChatMessage {
            metadata: None,
            from_device: "Bob".to_string(),
            body: "hello from bob".to_string(),
            message_id: Some(message_id.to_string()),
            sent_at_ms: Some(sent_at_ms),
            attachment: None,
            call_event: None,
            delivery_status: None,
            delivery_error: None,
            retryable: None,
            retry_count: None,
            read: None,
        };
        let record = crate::conversation::history::StoredMessage {
            conversation_id: invite.session_id.clone(),
            sent_at_ms,
            message_id: message_id.to_string(),
            message,
            attachment_manifest: None,
            preview_manifest: None,
        };
        persistence
            .append_message(
                &invite.session_id,
                sent_at_ms,
                message_id,
                &serde_json::to_vec(&record).expect("record should serialize"),
            )
            .expect("inbound message should persist");
        invite.session_id
    };

    let mut revived =
        PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), Some(persistence));
    revived.rehydrate();

    let listing = revived.list_sessions().expect("listing should pass");
    let session = listing
        .sessions
        .iter()
        .find(|session| session.session_id == session_id)
        .expect("session should rehydrate");

    assert_eq!(session.peer_display_name, "Bob");
    // The peer was here once, but nothing proves it is now.
    assert_eq!(session.state, DmSessionState::Handshaking);
    assert_eq!(session.messages.len(), 1);

    let _ = std::fs::remove_file(&db_path);
}

#[test]
fn history_and_session_survive_restart() {
    use crate::persistence::Persistence;
    use std::path::PathBuf;

    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut db_path: PathBuf = std::env::temp_dir();
    db_path.push(format!("mosh-dm-rehydrate-{}.redb", std::process::id()));
    let _ = std::fs::remove_file(&db_path);

    let persistence =
        Arc::new(Persistence::open_with_dek(&db_path, [9u8; 32]).expect("store should open"));

    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));

    // Runtime #1: create an invite + send one message, then drop it.
    let session_id = {
        let mut alice = PrivateDmRuntime::from_shared(
            Arc::clone(&runtime),
            temp_store(),
            Some(persistence.clone()),
        );
        let invite = alice
            .create_invite(StartSessionRequest {
                display_name: "Alice".to_string(),
                listen_port: 42140,
                static_peer: None,
            })
            .expect("Alice invite should be created");
        alice
            .send_message(&invite.session_id, "hello after restart".to_string())
            .expect("Alice should send");
        invite.session_id
    };

    // Runtime #2: rehydrate from the SAME store and prove the message is back.
    let mut revived = PrivateDmRuntime::from_shared(
        Arc::clone(&runtime),
        temp_store(),
        Some(persistence.clone()),
    );
    revived.rehydrate();

    let listing = revived.list_sessions().expect("listing should pass");
    let session = listing
        .sessions
        .iter()
        .find(|s| s.session_id == session_id)
        .expect("rehydrated session should be present");

    let matching: Vec<&ChatMessage> = session
        .messages
        .iter()
        .filter(|m| m.body == "hello after restart")
        .collect();
    assert_eq!(
        matching.len(),
        1,
        "expected exactly one rehydrated message, dup-guard failed: {:?}",
        session.messages
    );

    // Dup-guard: re-listing (which drains inbound + persists tail) must not
    // duplicate the loaded message.
    let listing2 = revived.list_sessions().expect("second listing should pass");
    let session2 = listing2
        .sessions
        .iter()
        .find(|s| s.session_id == session_id)
        .expect("session should still be present");
    let matching2 = session2
        .messages
        .iter()
        .filter(|m| m.body == "hello after restart")
        .count();
    assert_eq!(
        matching2, 1,
        "tail-persist re-append duplicated the message"
    );

    let _ = std::fs::remove_file(&db_path);
}

// Regression: peer_moss_id was not persisted, and nothing relearns it after
// the handshake completes (pump_handshake only resends while !peer_joined).
// A restarted client therefore fell into the unknown-id fallback forever:
// Connected against strangers, no dial target, and no addressable relayed
// send. The record is finalized before the id is learned, so this also
// covers the dirty-record rewrite.
#[test]
fn peer_moss_id_survives_a_restart() {
    use crate::persistence::Persistence;
    use std::path::PathBuf;

    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut db_path: PathBuf = std::env::temp_dir();
    db_path.push(format!("mosh-dm-peer-id-{}.redb", std::process::id()));
    let _ = std::fs::remove_file(&db_path);

    let persistence =
        Arc::new(Persistence::open_with_dek(&db_path, [23u8; 32]).expect("store should open"));
    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
    let peer_id = "ab".repeat(32);

    let session_id = {
        let mut alice = PrivateDmRuntime::from_shared(
            Arc::clone(&runtime),
            temp_store(),
            Some(persistence.clone()),
        );
        let invite = alice
            .create_invite(StartSessionRequest {
                display_name: "Alice".to_string(),
                listen_port: 42162,
                static_peer: None,
            })
            .expect("Alice invite should be created");

        // What handle_control does with the peer's KeyPackage. Alice's MLS
        // group already exists, so the record was finalized at invite time.
        alice
            .sessions
            .get_mut(&invite.session_id)
            .expect("Alice session should exist")
            .note_peer_moss_id(Some(peer_id.clone()));
        alice
            .poll_session(&invite.session_id)
            .expect("poll should re-persist the dirtied record");
        invite.session_id
    };

    let mut revived =
        PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), Some(persistence));
    revived.rehydrate();
    let session = revived
        .sessions
        .get(&session_id)
        .expect("session should rehydrate");
    assert_eq!(
        session.peer_moss_id.as_deref(),
        Some(peer_id.as_str()),
        "the restored session must still know which peer is its counterpart"
    );

    let _ = std::fs::remove_file(&db_path);
}

// Regression: the invite *joiner* (Bob) only obtains an MLS group after he
// processes Alice's Welcome, so his persisted session record must be
// refreshed with the real group_id once joined. Otherwise rehydrate cannot
// load the group and the whole conversation is silently dropped on restart.
//
// Needs a real two-node loopback handshake, which is timing-flaky, so it is
// on-demand (`cargo test -- --ignored`). The group_id-refresh logic itself
// is also exercised by the crypto restore tests.
#[test]
#[ignore]
fn joiner_history_and_session_survive_restart() {
    use crate::persistence::Persistence;
    use std::path::PathBuf;

    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut db_path: PathBuf = std::env::temp_dir();
    db_path.push(format!(
        "mosh-dm-joiner-rehydrate-{}.redb",
        std::process::id()
    ));
    let _ = std::fs::remove_file(&db_path);

    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));

    // Alice (creator) is memory-only; Bob (joiner) is the one that persists.
    let bob_store =
        Arc::new(Persistence::open_with_dek(&db_path, [7u8; 32]).expect("store should open"));

    let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
    let invite = alice
        .create_invite(StartSessionRequest {
            display_name: "Alice".to_string(),
            listen_port: 42150,
            static_peer: None,
        })
        .expect("Alice invite should be created");

    let session_id = {
        let mut bob = PrivateDmRuntime::from_shared(
            Arc::clone(&runtime),
            temp_store(),
            Some(bob_store.clone()),
        );
        bob.accept_invite(AcceptInviteRequest {
            invite_uri: invite.invite_uri.clone(),
            display_name: "Bob".to_string(),
            listen_port: 42151,
            static_peer: Some("127.0.0.1:42150".to_string()),
        })
        .expect("Bob should accept invite");

        wait_until_ready(&mut alice, &mut bob, &invite.session_id);
        bob.send_message(&invite.session_id, "joiner persists".to_string())
            .expect("Bob should send");
        invite.session_id.clone()
    };

    // Bob "restarts": brand-new runtime, same encrypted store.
    let mut revived =
        PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), Some(bob_store));
    revived.rehydrate();

    let listing = revived.list_sessions().expect("listing should pass");
    let session = listing
        .sessions
        .iter()
        .find(|s| s.session_id == session_id)
        .expect("rehydrated joiner session should be present");
    assert!(
        session.messages.iter().any(|m| m.body == "joiner persists"),
        "joiner message lost across restart: {:?}",
        session.messages
    );

    let _ = std::fs::remove_file(&db_path);
}
