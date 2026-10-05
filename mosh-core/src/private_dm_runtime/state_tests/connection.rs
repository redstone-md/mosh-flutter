use super::*;

// next_state(current, event)
#[test]
fn state_moves_only_on_evidence() {
    use DmSessionState::*;
    use SessionEvent::*;
    assert_eq!(next_state(Pending, HandshakeFrame), Handshaking);
    assert_eq!(next_state(Pending, AuthenticatedFrame), Connected);
    assert_eq!(next_state(Pending, CounterpartLost), Pending);
    assert_eq!(next_state(Handshaking, HandshakeFrame), Handshaking);
    assert_eq!(next_state(Handshaking, AuthenticatedFrame), Connected);
    assert_eq!(next_state(Handshaking, CounterpartLost), Handshaking);
    assert_eq!(next_state(Connected, HandshakeFrame), Connected);
    assert_eq!(next_state(Connected, AuthenticatedFrame), Connected);
    assert_eq!(next_state(Connected, CounterpartLost), Handshaking);
}

// The state sequence on both sides of a handshake. Alice sees the KeyPackage
// (handshaking), then Bob's Hello (connected). Bob sees the Welcome and
// Alice's Hello in the same drain, so his snapshot goes straight to connected.
#[test]
fn a_handshake_proves_both_sides_to_each_other() {
    let (_net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    assert_eq!(
        state_of(&mut alice, &invite.session_id),
        DmSessionState::Pending
    );
    accept(&mut bob, &invite);
    assert_eq!(
        state_of(&mut bob, &invite.session_id),
        DmSessionState::Pending
    );

    assert_eq!(
        state_of(&mut alice, &invite.session_id),
        DmSessionState::Handshaking
    );
    assert_eq!(
        state_of(&mut bob, &invite.session_id),
        DmSessionState::Connected
    );
    let alice_view = alice
        .poll_session(&invite.session_id)
        .expect("poll should pass");
    assert_eq!(alice_view.state, DmSessionState::Connected);
    assert_eq!(alice_view.transport, PeerTransport::Direct);
    assert_eq!(alice_view.peer_moss_id.as_deref(), Some(BOB_ID));
    assert_eq!(
        alice_view.last_connect_outcome,
        Some(ConnectOutcome::Requested)
    );
    let bob_view = bob
        .poll_session(&invite.session_id)
        .expect("poll should pass");
    assert_eq!(bob_view.transport, PeerTransport::Direct);
    assert_eq!(bob_view.peer_moss_id.as_deref(), Some(ALICE_ID));
}

// Connected needs the other side's word, not our own handshake work: with
// Bob's Hello lost, Alice stays handshaking until anything authenticated
// arrives from him.
#[test]
fn a_lost_hello_keeps_the_inviter_handshaking() {
    let (net, mut alice, mut bob) = memory_pair();
    net.drop_frames(BOB_ID, ALICE_ID, |_, payload| {
        payload_says(payload, "Hello")
    });
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);

    for _ in 0..3 {
        assert_eq!(
            state_of(&mut alice, &invite.session_id),
            DmSessionState::Handshaking
        );
        assert_eq!(
            state_of(&mut bob, &invite.session_id),
            DmSessionState::Connected
        );
    }

    bob.send_message(&invite.session_id, "proof".to_string())
        .expect("Bob should send");
    assert_eq!(
        state_of(&mut alice, &invite.session_id),
        DmSessionState::Connected
    );
}

// Connected is a claim about now: once nothing authenticated has come from
// the counterpart for the lost window the session says so, and the next
// authenticated frame takes it back. The tick takes its clock as an argument,
// so the window is crossed by arithmetic, not by sleeping.
#[test]
fn connected_degrades_after_the_lost_window_and_recovers_on_a_frame() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);

    net.link(ALICE_ID, BOB_ID, PeerTransport::None);
    let gone_at = now_ms();
    alice.tick(gone_at);
    assert_eq!(
        state_of(&mut alice, &invite.session_id),
        DmSessionState::Connected,
        "a moment of silence is not a verdict"
    );
    alice.tick(gone_at + LOST_WINDOW_MS);
    let view = alice
        .poll_session(&invite.session_id)
        .expect("poll should pass");
    assert_eq!(view.state, DmSessionState::Handshaking);
    assert_eq!(view.transport, PeerTransport::None);

    bob.send_message(&invite.session_id, "back".to_string())
        .expect("Bob still reaches Alice");
    assert_eq!(
        state_of(&mut alice, &invite.session_id),
        DmSessionState::Connected
    );
}

// A duplicate inbound Data frame (peer re-sent because our ack was lost)
// must re-ack from the stored message id, never re-decrypt.
#[test]
fn duplicate_inbound_data_reacks_without_decrypt() {
    let net = MemoryNet::new();
    net.link(ALICE_ID, BOB_ID, PeerTransport::Direct);
    let bob_end = net.endpoint(BOB_ID);
    let mut alice = runtime_on(&net, ALICE_ID);
    let invite = invite(&mut alice);

    let session = alice
        .sessions
        .get_mut(&invite.session_id)
        .expect("Alice session should exist");
    // Seed the already-received inbound message.
    session.messages.push(ChatMessage {
        metadata: None,
        from_device: "Peer".to_string(),
        body: "hi".to_string(),
        message_id: Some("m-dup".to_string()),
        sent_at_ms: Some(1),
        attachment: None,
        call_event: None,
        delivery_status: None,
        delivery_error: None,
        retryable: None,
        retry_count: None,
        read: None,
    });
    let dup = serde_json::to_vec(&DataEnvelope {
        origin: None,
        device_signature: None,
        session_id: invite.session_id.clone(),
        participant_id: "peer-participant".to_string(),
        from_device: "Peer".to_string(),
        message_id: Some("m-dup".to_string()),
        sent_at_ms: Some(1),
        // Garbage ciphertext: decrypt would fail, proving the re-ack
        // path returns before touching MLS.
        ciphertext_b64: encode(b"not-a-ciphertext"),
        resend: Some(1),
    })
    .expect("dup should serialize");
    session.handle_data(dup).expect("dup must not error");

    let frames = bob_end.drain();
    let ack = frames
        .iter()
        .find(|frame| frame.channel == control_channel(&invite.session_id))
        .expect("re-ack should go out on the control channel");
    assert!(payload_says(&ack.payload, "DeliveryAck"));
    assert!(
        payload_says(&ack.payload, "ack_ciphertext_b64") && !payload_says(&ack.payload, "m-dup"),
        "acked id travels encrypted, never in the clear"
    );
}

// An inbound frame that decrypts is the counterpart's word that it is here:
// the session is Connected from that frame alone, whatever the transport
// reported so far.
#[test]
fn a_decrypted_inbound_frame_proves_the_connection() {
    let net = MemoryNet::new();
    let mut alice = runtime_on(&net, ALICE_ID);
    let invite = invite(&mut alice);

    let mut bob_crypto = MlsSessionCrypto::new("Bob").expect("Bob crypto should init");
    let key_package = bob_crypto
        .key_package_bytes()
        .expect("Bob key package should build");
    let session = alice
        .sessions
        .get_mut(&invite.session_id)
        .expect("Alice session should exist");
    let (welcome, tree) = session
        .crypto
        .add_peer(&key_package)
        .expect("Alice should add Bob");
    bob_crypto
        .join_welcome(&welcome, &tree)
        .expect("Bob should join");
    let ciphertext = bob_crypto
        .encrypt(b"hello after flag loss")
        .expect("Bob should encrypt");
    let payload = serde_json::to_vec(&DataEnvelope {
        origin: None,
        device_signature: None,
        session_id: invite.session_id.clone(),
        participant_id: "bob-participant".to_string(),
        from_device: "Bob".to_string(),
        message_id: Some("live-inbound-000001".to_string()),
        sent_at_ms: Some(2),
        ciphertext_b64: encode(&ciphertext),
        resend: None,
    })
    .expect("data envelope should serialize");

    assert_eq!(session.state, DmSessionState::Pending);
    session
        .handle_data(payload)
        .expect("Alice should decrypt inbound data");
    assert_eq!(session.state, DmSessionState::Connected);
    assert_eq!(session.peer_display_name.as_deref(), Some("Bob"));
}

#[test]
fn a_relayed_counterpart_reads_as_relayed() {
    let (net, mut alice, mut bob) = memory_pair();
    net.link_both(ALICE_ID, BOB_ID, PeerTransport::Relayed);
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    let view = alice
        .poll_session(&invite.session_id)
        .expect("poll should pass");
    assert_eq!(view.transport, PeerTransport::Relayed);
}

// The full settlement: Alice sends, Bob's runtime stores it (Delivered), Bob
// opens the conversation (mark_viewed, toggle on), and Alice's snapshot says
// `read: Some(true)` — with a message_read event filed on BOTH sides. The
// ticks' color is Dart's job; the field is the contract here.
