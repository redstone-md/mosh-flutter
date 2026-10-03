use super::*;

// Task 3: the moss peer-id rides along in the KeyPackage so Alice can
// learn Bob's relay address without a separate exchange.
#[test]
fn handle_control_captures_peer_moss_id_from_key_package() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
    let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
    let invite = alice
        .create_invite(StartSessionRequest {
            display_name: "Alice".to_string(),
            listen_port: 42183,
            static_peer: None,
        })
        .expect("Alice invite should be created");

    let mut bob_crypto = MlsSessionCrypto::new("Bob").expect("Bob crypto should init");
    let key_package_b64 = encode(
        &bob_crypto
            .key_package_bytes()
            .expect("Bob key package should build"),
    );
    let bob_moss_peer_id = "ab".repeat(32);
    let payload = serde_json::to_vec(&ControlEnvelope::KeyPackage {
        session_id: invite.session_id.clone(),
        participant_id: "bob-participant".to_string(),
        from_device: "Bob".to_string(),
        key_package_b64,
        moss_peer_id: Some(bob_moss_peer_id.clone()),
    })
    .expect("KeyPackage envelope should serialize");

    let session = alice
        .sessions
        .get_mut(&invite.session_id)
        .expect("Alice session should exist");

    session
        .handle_control(payload)
        .expect("KeyPackage should add Bob");
    assert_eq!(session.peer_moss_id, Some(bob_moss_peer_id));
}

// A peer that restarts without a persisted moss identity re-handshakes
// under a fresh peer-id; the latest KeyPackage must replace the stale pin
// or every relayed send keeps targeting a dead id.
#[test]
fn key_package_with_new_moss_id_replaces_stale_pin() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
    let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
    let invite = alice
        .create_invite(StartSessionRequest {
            display_name: "Alice".to_string(),
            listen_port: 42187,
            static_peer: None,
        })
        .expect("Alice invite should be created");

    let mut bob_crypto = MlsSessionCrypto::new("Bob").expect("Bob crypto should init");
    let key_package_b64 = encode(
        &bob_crypto
            .key_package_bytes()
            .expect("Bob key package should build"),
    );
    let make_payload = |moss_peer_id: String| {
        serde_json::to_vec(&ControlEnvelope::KeyPackage {
            session_id: invite.session_id.clone(),
            participant_id: "bob-participant".to_string(),
            from_device: "Bob".to_string(),
            key_package_b64: key_package_b64.clone(),
            moss_peer_id: Some(moss_peer_id),
        })
        .expect("KeyPackage envelope should serialize")
    };

    let session = alice
        .sessions
        .get_mut(&invite.session_id)
        .expect("Alice session should exist");
    session
        .handle_control(make_payload("ab".repeat(32)))
        .expect("first KeyPackage should add Bob");
    assert_eq!(session.peer_moss_id, Some("ab".repeat(32)));

    session
        .handle_control(make_payload("cd".repeat(32)))
        .expect("resent KeyPackage should be handled");
    assert_eq!(
        session.peer_moss_id,
        Some("cd".repeat(32)),
        "restarted peer's fresh moss id should replace the stale pin"
    );
}

// The peer's DeliveryAck upgrades Sent → Delivered and retires the
// attempt (stopping the auto-resend loop).
#[test]
fn forged_delivery_ack_does_not_upgrade() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
    let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
    let invite = alice
        .create_invite(StartSessionRequest {
            display_name: "Alice".to_string(),
            listen_port: 42194,
            static_peer: None,
        })
        .expect("Alice invite should be created");

    // No peer is known yet, so the text waits in the queue.
    let result = alice
        .send_message(&invite.session_id, "ping".to_string())
        .expect("send should queue");
    assert_eq!(result.delivery_status, MessageDeliveryStatus::Queued);

    // Forgery #1: garbage ciphertext — an attacker without the MLS group
    // secrets cannot produce anything that decrypts.
    let forged = serde_json::to_vec(&ControlEnvelope::DeliveryAck {
        session_id: invite.session_id.clone(),
        participant_id: "peer-participant".to_string(),
        ack_ciphertext_b64: encode(b"not-an-mls-ciphertext"),
    })
    .expect("ack should serialize");
    // Forgery #2: a REPLAYED ciphertext minted by this very group member
    // (MLS cannot decrypt own messages, so even this is rejected).
    let self_minted = {
        let session = alice
            .sessions
            .get_mut(&invite.session_id)
            .expect("Alice session should exist");
        let ciphertext = session
            .crypto
            .encrypt(result.message_id.as_bytes())
            .expect("encrypt should work");
        serde_json::to_vec(&ControlEnvelope::DeliveryAck {
            session_id: invite.session_id.clone(),
            participant_id: "peer-participant".to_string(),
            ack_ciphertext_b64: encode(&ciphertext),
        })
        .expect("ack should serialize")
    };

    let session = alice
        .sessions
        .get_mut(&invite.session_id)
        .expect("Alice session should exist");
    session
        .handle_control(forged)
        .expect("forged ack must not error");
    session
        .handle_control(self_minted)
        .expect("replayed ack must not error");

    let session = &alice.sessions[&invite.session_id];
    assert!(
        session.outbound_attempts.contains_key(&result.message_id),
        "attempt must survive forged acks"
    );
    let message = session
        .messages
        .iter()
        .find(|m| m.message_id.as_deref() == Some(result.message_id.as_str()))
        .expect("message exists");
    assert_eq!(
        message.delivery_status,
        Some(MessageDeliveryStatus::Queued),
        "no forged Delivered"
    );
}

// Sessions restored from a record written before peer_moss_id was persisted
// carry None and nothing else recovers it, so the peer must be able to
// re-announce out of band. Repairs history rather than requiring a new DM.
#[test]
fn a_peer_announce_restores_a_lost_peer_id() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let (mut alice, session_id) = lone_session(42163);
    let session = alice
        .sessions
        .get_mut(&session_id)
        .expect("Alice session should exist");

    // The shape a pre-fix record rehydrates into: joined, but peerless.
    session.peer_joined = true;
    session.peer_moss_id = None;
    session.record_dirty = false;

    let peer_id = "ab".repeat(32);
    let announce = serde_json::to_vec(&ControlEnvelope::PeerAnnounce {
        session_id: session_id.clone(),
        participant_id: "the-other-participant".to_string(),
        from_device: "Bob".to_string(),
        moss_peer_id: peer_id.clone(),
    })
    .expect("announce should serialize");

    session
        .handle_control(announce)
        .expect("announce should be accepted");
    assert_eq!(
        session.peer_moss_id.as_deref(),
        Some(peer_id.as_str()),
        "the announce is what relearns the counterpart"
    );
    assert!(
        session.record_dirty,
        "the relearned id must be written back, or the next restart loses it again"
    );
}

// The announce is a repair path: it must fire only while the id is missing,
// and must not flood while it is.
#[test]
fn peer_announce_fires_only_while_the_id_is_missing() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let (mut alice, session_id) = lone_session(42164);
    let session = alice
        .sessions
        .get_mut(&session_id)
        .expect("Alice session should exist");

    session.peer_joined = true;
    session.peer_moss_id = Some("ab".repeat(32));
    session.pump_peer_announce(10_000);
    assert_eq!(
        session.last_peer_announce_ms, 0,
        "a session that knows its peer never announces"
    );

    session.peer_moss_id = None;
    session.pump_peer_announce(10_000);
    assert_eq!(session.last_peer_announce_ms, 10_000);

    session.pump_peer_announce(10_000 + PEER_ANNOUNCE_RESEND_MS - 1);
    assert_eq!(
        session.last_peer_announce_ms, 10_000,
        "announces inside the throttle window are suppressed"
    );

    let due = 10_000 + PEER_ANNOUNCE_RESEND_MS;
    session.pump_peer_announce(due);
    assert_eq!(session.last_peer_announce_ms, due);
}

// Two conversations share the one node the holder keeps, and the node
// goes down with the last of them. Two nodes would present the same peer
// id from two ports and a remote peer would keep one.
#[test]
fn sessions_share_one_node_and_close_releases_it() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
    let holder = SharedMossNode::new(runtime);
    let mut alice = PrivateDmRuntime::from_shared_node(Arc::clone(&holder), temp_store(), None);
    let first = alice
        .create_invite(StartSessionRequest {
            display_name: "Alice".to_string(),
            listen_port: 42187,
            static_peer: None,
        })
        .expect("first invite should be created");
    let node_ptr = Arc::as_ptr(&holder.current().expect("the node is up"));
    let second = alice
        .create_invite(StartSessionRequest {
            display_name: "Alice".to_string(),
            listen_port: 42188,
            static_peer: None,
        })
        .expect("second invite should be created");
    assert_eq!(
        node_ptr,
        Arc::as_ptr(&holder.current().expect("the node is still up")),
        "the second conversation started a second moss node"
    );
    assert_ne!(
        alice.sessions[&first.session_id].mesh_id, alice.sessions[&second.session_id].mesh_id,
        "sessions must stay in separate rooms on the shared node"
    );

    // Closing one leaves the node up for the other...
    alice
        .close_session(&first.session_id)
        .expect("first session should close");
    assert!(
        holder.current().is_some(),
        "the shared node went down while a conversation was still open"
    );
    // ...and closing the last one takes it down.
    alice
        .close_session(&second.session_id)
        .expect("second session should close");
    assert!(
        holder.current().is_none(),
        "the shared node outlived every conversation — nothing would ever stop moss"
    );
}

// Real two-node loopback: one node per installation serves the handshake
// and a message, and no second node ever appears. Every snapshot along
// the way names the substrate room, which only the one node is born in.
// Timing-sensitive like the other loopback tests, so on demand
// (`cargo test -- --ignored`).
#[test]
#[ignore]
fn one_node_serves_the_handshake_and_a_message() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();
    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
    let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
    let invite = alice
        .create_invite(StartSessionRequest {
            display_name: "Alice".to_string(),
            listen_port: 42132,
            static_peer: None,
        })
        .expect("Alice invite should be created");
    let mut bob = PrivateDmRuntime::from_shared(runtime, temp_store(), None);
    bob.accept_invite(AcceptInviteRequest {
        invite_uri: invite.invite_uri.clone(),
        display_name: "Bob".to_string(),
        listen_port: 42133,
        static_peer: Some("127.0.0.1:42132".to_string()),
    })
    .expect("Bob should accept invite");

    wait_until_ready(&mut alice, &mut bob, &invite.session_id);
    alice
        .send_message(&invite.session_id, "one node".to_string())
        .expect("Alice should send");
    let snapshot = wait_for_message(&mut bob, &invite.session_id, "one node");

    for view in [
        snapshot,
        alice
            .poll_session(&invite.session_id)
            .expect("Alice poll should pass"),
    ] {
        assert_eq!(view.state, DmSessionState::Connected);
        assert_ne!(view.transport, PeerTransport::None);
        assert_eq!(
            view.mesh.expect("the node reports").mesh_id,
            crate::shared_node::SUBSTRATE_ROOM,
            "a DM frame went through a node born in some other mesh"
        );
    }
}
