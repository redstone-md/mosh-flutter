use super::*;

// next_path(current, direct_now, direct_stable, direct_gone, elapsed, t_fallback)

// Real two-node loopback handshake; the gossipsub mesh occasionally fails
// to form in time, so this is an on-demand smoke test (run with
// `cargo test -- --ignored`). The persistence/resume logic it exercises is
// covered deterministically by the crypto restore tests and the
// handshake-free history_and_session_survive_restart.
#[test]
#[ignore]
fn private_dm_runtime_exchanges_e2ee_message_over_moss() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();
    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
    let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
    let invite = alice
        .create_invite(StartSessionRequest {
            display_name: "Alice".to_string(),
            listen_port: 42130,
            static_peer: None,
        })
        .expect("Alice invite should be created");

    let mut bob = PrivateDmRuntime::from_shared(runtime, temp_store(), None);
    bob.accept_invite(AcceptInviteRequest {
        invite_uri: invite.invite_uri.clone(),
        display_name: "Bob".to_string(),
        listen_port: 42131,
        static_peer: Some("127.0.0.1:42130".to_string()),
    })
    .expect("Bob should accept invite");

    wait_until_ready(&mut alice, &mut bob, &invite.session_id);
    let sent = alice
        .send_message(&invite.session_id, "hello bob".to_string())
        .expect("Alice should send");

    let snapshot = wait_for_message(&mut bob, &invite.session_id, "hello bob");
    assert_eq!(snapshot.state, DmSessionState::Connected);

    // Bob's runtime acks on receipt; Alice's message must reach the
    // Delivered (✓✓) state once she drains the ack.
    let mut delivered = false;
    for _ in 0..40 {
        let _ = bob.poll_session(&invite.session_id);
        let alice_view = alice
            .poll_session(&invite.session_id)
            .expect("poll should pass");
        if alice_view.messages.iter().any(|m| {
            m.message_id.as_deref() == Some(sent.message_id.as_str())
                && m.delivery_status == Some(MessageDeliveryStatus::Delivered)
        }) {
            delivered = true;
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(100));
    }
    assert!(delivered, "Alice's message never reached Delivered");
}

// The invite embeds the creator's moss peer id and accept_invite must copy
// it onto the session, or a hard-NAT joiner cannot relay the handshake
// before the first direct window teaches it the id.
#[test]
fn accept_invite_preseeds_peer_moss_id_from_the_invite() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
    let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
    let invite = alice
        .create_invite(StartSessionRequest {
            display_name: "Alice".to_string(),
            listen_port: 42190,
            static_peer: None,
        })
        .expect("Alice invite should be created");
    let parsed = super::super::invite::ParsedInvite::parse(&invite.invite_uri)
        .expect("invite should decode and verify");

    let mut bob = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
    bob.accept_invite(AcceptInviteRequest {
        invite_uri: invite.invite_uri.clone(),
        display_name: "Bob".to_string(),
        listen_port: 42191,
        static_peer: Some("127.0.0.1:42190".to_string()),
    })
    .expect("Bob should accept invite");

    let alice_id = alice
        .sessions
        .get(&invite.session_id)
        .expect("Alice session should exist")
        .transport
        .local_peer_id()
        .expect("Alice node should expose its key");
    assert_eq!(parsed.peer_moss_id.as_deref(), Some(alice_id.as_str()));
    let bob_session = bob
        .sessions
        .get(&invite.session_id)
        .expect("Bob session should exist");
    assert_eq!(bob_session.peer_moss_id.as_deref(), Some(alice_id.as_str()));
}

// On the room-blind shared substrate two DM endpoints only ever connect by
// chance, so each session must hand its counterpart's moss id to moss as an
// explicit connect target the moment the id is known: Bob from the invite,
// Alice from the first handshake frame; a re-handshake under a fresh id
// must re-register.
#[test]
fn sessions_request_explicit_connect_to_counterpart() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
    let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
    let invite = alice
        .create_invite(StartSessionRequest {
            display_name: "Alice".to_string(),
            listen_port: 42172,
            static_peer: None,
        })
        .expect("Alice invite should be created");

    let mut bob = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
    bob.accept_invite(AcceptInviteRequest {
        invite_uri: invite.invite_uri.clone(),
        display_name: "Bob".to_string(),
        listen_port: 42173,
        static_peer: Some("127.0.0.1:42172".to_string()),
    })
    .expect("Bob should accept invite");

    // Bob's id was preseeded from the invite, so the accept-time drain tick
    // must already have registered the explicit target.
    let bob_session = bob
        .sessions
        .get(&invite.session_id)
        .expect("Bob session should exist");
    assert_eq!(
        bob_session.connect_requested_for, bob_session.peer_moss_id,
        "Bob requests an explicit connect to the invite's moss id"
    );
    assert!(bob_session.connect_requested_for.is_some());

    // Alice has not learned Bob's id yet: nothing to request.
    let alice_session = alice
        .sessions
        .get_mut(&invite.session_id)
        .expect("Alice session should exist");
    assert_eq!(alice_session.connect_requested_for, None);

    // Alice learns the id -> the next pump registers it.
    let bob_id = "cd".repeat(32);
    alice_session.peer_moss_id = Some(bob_id.clone());
    alice_session.pump_peer_connect();
    assert_eq!(
        alice_session.connect_requested_for.as_deref(),
        Some(bob_id.as_str())
    );

    // Peer re-handshakes under a fresh moss identity -> re-register.
    let fresh_id = "ef".repeat(32);
    alice_session.peer_moss_id = Some(fresh_id.clone());
    alice_session.pump_peer_connect();
    assert_eq!(
        alice_session.connect_requested_for.as_deref(),
        Some(fresh_id.as_str())
    );
}

// D2 regression: the KeyPackage->Welcome handshake is a one-shot publish.
// If it lands before the mesh link forms it is lost, and nothing used to
// re-send it, so the session hung on "waiting" forever even after the peer
// joined the transport. Bob must keep the KeyPackage and re-send it until
// he joins.
#[test]
fn bob_retransmits_key_package_until_joined() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
    let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
    let invite = alice
        .create_invite(StartSessionRequest {
            display_name: "Alice".to_string(),
            listen_port: 42180,
            static_peer: None,
        })
        .expect("Alice invite should be created");

    let mut bob = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
    bob.accept_invite(AcceptInviteRequest {
        invite_uri: invite.invite_uri.clone(),
        display_name: "Bob".to_string(),
        listen_port: 42181,
        static_peer: Some("127.0.0.1:42180".to_string()),
    })
    .expect("Bob should accept invite");

    let session = bob
        .sessions
        .get_mut(&invite.session_id)
        .expect("Bob session should exist");
    assert!(
        session.pending_key_package.is_some(),
        "Bob retains the KeyPackage for retransmit"
    );
    assert!(!session.peer_joined);

    // Throttle from a known baseline (accept_invite stamped real-now).
    session.last_handshake_send_ms = 0;
    assert!(
        session.handshake_resend_due(HANDSHAKE_RESEND_MS + 1),
        "resend is due once the throttle window elapses"
    );
    assert!(
        !session.handshake_resend_due(HANDSHAKE_RESEND_MS - 1),
        "resend is suppressed inside the throttle window"
    );

    // Welcome processed -> handshake complete -> stop retransmitting.
    session.peer_joined = true;
    session.pump_handshake(HANDSHAKE_RESEND_MS * 10);
    assert!(
        session.pending_key_package.is_none(),
        "joining clears the pending KeyPackage"
    );
    assert!(!session.handshake_resend_due(HANDSHAKE_RESEND_MS * 100));
}

// D2 regression: Alice's Welcome can also be lost before Bob meshes. Since
// add_members cannot run twice (it would advance the group epoch), Alice
// must cache the Welcome and re-answer Bob's repeated KeyPackage with it.
#[test]
fn alice_caches_welcome_and_reanswers_repeat_key_package() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
    let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
    let invite = alice
        .create_invite(StartSessionRequest {
            display_name: "Alice".to_string(),
            listen_port: 42182,
            static_peer: None,
        })
        .expect("Alice invite should be created");

    let mut bob_crypto = MlsSessionCrypto::new("Bob").expect("Bob crypto should init");
    let key_package_b64 = encode(
        &bob_crypto
            .key_package_bytes()
            .expect("Bob key package should build"),
    );
    let payload = serde_json::to_vec(&ControlEnvelope::KeyPackage {
        session_id: invite.session_id.clone(),
        participant_id: "bob-participant".to_string(),
        from_device: "Bob".to_string(),
        key_package_b64,
        moss_peer_id: None,
    })
    .expect("KeyPackage envelope should serialize");

    let session = alice
        .sessions
        .get_mut(&invite.session_id)
        .expect("Alice session should exist");

    session
        .handle_control(payload.clone())
        .expect("first KeyPackage should add Bob");
    assert!(session.peer_joined);
    assert!(
        session.pending_welcome.is_some(),
        "Alice caches the Welcome she produced"
    );
    assert_eq!(session.crypto.member_count(), 2);

    // Bob's retransmit must be re-answered, never trigger a second add.
    session
        .handle_control(payload)
        .expect("repeat KeyPackage should re-answer with the cached Welcome");
    assert_eq!(
        session.crypto.member_count(),
        2,
        "repeat KeyPackage must not re-run add_members"
    );
    assert!(session.pending_welcome.is_some());
}

// The dedup above handle_control is what made every D2 retransmit fix
// ineffective in the field. Bob re-sends the *identical* KeyPackage bytes,
// so a payload-hash dedup drops every copy after the first and the
// re-answer path never runs — a session whose first Welcome was lost hung
// on "waiting" forever. The existing handshake tests call handle_control
// directly and so never crossed this layer.
#[test]
fn repeat_control_frames_reach_the_handler_while_data_still_dedups() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
    let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
    let invite = alice
        .create_invite(StartSessionRequest {
            display_name: "Alice".to_string(),
            listen_port: 42184,
            static_peer: None,
        })
        .expect("Alice invite should be created");
    let session = alice
        .sessions
        .get_mut(&invite.session_id)
        .expect("Alice session should exist");

    let bytes = b"identical retransmission".to_vec();
    let control = MossReceivedMessage {
        channel: session.control_channel.clone(),
        payload: bytes.clone(),
    };
    let data = MossReceivedMessage {
        channel: session.data_channel.clone(),
        payload: bytes,
    };

    assert!(!session.has_seen_message(&control));
    assert!(
        !session.has_seen_message(&control),
        "an identical control frame must still reach handle_control — \
             re-sending it unchanged is how the handshake recovers"
    );

    // Data frames keep deduping, or a resent message doubles in history.
    assert!(!session.has_seen_message(&data));
    assert!(
        session.has_seen_message(&data),
        "a repeated data frame must be suppressed"
    );
}
