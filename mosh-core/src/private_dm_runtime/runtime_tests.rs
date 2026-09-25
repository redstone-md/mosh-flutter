//! The DM runtime integration tests over the real Moss loopback.
use super::*;

use crate::attachment_runtime::CHUNK_SIZE;
use crate::moss_ffi::{drain_received_messages, MossFfiRuntime, MOSS_TEST_LOCK};

pub(super) fn temp_store() -> Arc<AttachmentStore> {
    let mut path = std::env::temp_dir();
    path.push(format!(
        "mosh-dm-attachments-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    Arc::new(AttachmentStore::new(&path).expect("attachment store should init"))
}

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
    assert!(
        invite.invite_uri.contains("&moss="),
        "invite must carry the creator moss id: {}",
        invite.invite_uri
    );

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

// The same dedup, one channel over. A receiver missing chunk 7 asks for
// chunk 7 again, and that request is byte-identical to the last one, so
// every repeat was dropped before handle_blob and the sender never
// re-served — the transfer hung at 63% for good. Driven through
// handle_moss_message on purpose: the attachment tests call the handlers
// directly and so never cross the layer the bug lives in.
#[test]
fn a_repeated_chunk_request_still_reaches_the_sender() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
    let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
    let invite = alice
        .create_invite(StartSessionRequest {
            display_name: "Alice".to_string(),
            listen_port: 42186,
            static_peer: None,
        })
        .expect("Alice invite should be created");
    let session = alice
        .sessions
        .get_mut(&invite.session_id)
        .expect("Alice session should exist");

    session
        .transfer
        .prepare_outgoing(OutgoingAttachment {
            attachment_id: "att-1".to_string(),
            file_name: "photo.bin".to_string(),
            mime: "application/octet-stream".to_string(),
            from_fingerprint: session.fingerprint.clone(),
            bytes: vec![7u8; 512],
            thumbnail_b64: None,
            voice: None,
        })
        .expect("outgoing attachment should register");

    let payload = serde_json::to_vec(&BlobEnvelope::Request {
        participant_id: "peer-participant".to_string(),
        request: crate::attachment_runtime::ChunkRequest {
            attachment_id: "att-1".to_string(),
            chunk_indices: vec![0],
        },
    })
    .expect("blob request should serialize");
    let request = MossReceivedMessage {
        channel: session.blob_channel.clone(),
        payload,
    };

    session
        .handle_moss_message(request.clone())
        .expect("first chunk request should be served");
    session
        .handle_moss_message(request)
        .expect("repeat chunk request should be served again");
    assert_eq!(
        session.transfer.served_count("att-1", 0),
        2,
        "an identical re-request must reach handle_blob — re-asking \
             unchanged is how a lost chunk is recovered"
    );
}

// The stream carrier (spec #8) at the real-library seam: Alice has the
// counterpart's moss id but the node has nobody connected, so every
// stream send answers NoPeers and the carrier must fall back to the room
// wire — the chunk still reaches handle_blob as a room frame, byte for
// byte the pre-carrier payload. This is the mixed-version behavior too:
// a streamless counterpart never sees the framing.
#[test]
fn chunk_serving_falls_back_to_the_room_wire_when_the_stream_refuses() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
    let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
    let invite = alice
        .create_invite(StartSessionRequest {
            display_name: "Alice".to_string(),
            listen_port: 42188,
            static_peer: None,
        })
        .expect("Alice invite should be created");
    let session = alice
        .sessions
        .get_mut(&invite.session_id)
        .expect("Alice session should exist");

    // The stream fast path requires a known peer id; give the session
    // one, but leave the node unmeshed so both the stream and the room
    // refuse. The transfer must still record the serve attempt.
    session.peer_moss_id = Some("ab".repeat(32));

    session
        .transfer
        .prepare_outgoing(OutgoingAttachment {
            attachment_id: "att-stream-1".to_string(),
            file_name: "photo.bin".to_string(),
            mime: "application/octet-stream".to_string(),
            from_fingerprint: session.fingerprint.clone(),
            bytes: vec![7u8; 512],
            thumbnail_b64: None,
            voice: None,
        })
        .expect("outgoing attachment should register");

    let payload = serde_json::to_vec(&BlobEnvelope::Request {
        participant_id: "peer-participant".to_string(),
        request: crate::attachment_runtime::ChunkRequest {
            attachment_id: "att-stream-1".to_string(),
            chunk_indices: vec![0],
        },
    })
    .expect("blob request should serialize");
    let request = MossReceivedMessage {
        channel: session.blob_channel.clone(),
        payload,
    };

    session
        .handle_moss_message(request)
        .expect("serving through the failing carrier should not fail the request");

    assert_eq!(
        session.transfer.served_count("att-stream-1", 0),
        1,
        "the chunk was served (the room wire accepted the frame as always)"
    );

    // The room wire is the fallback, not a duplicate: with no stream
    // peer the fallback carries the frame, and nothing stream-shaped
    // leaked into the process inbox.
    let drained = drain_received_messages();
    assert!(
        drained
            .iter()
            .all(|message| !crate::stream_transport::is_stream_inbound(&message.channel)),
        "no stream-carried frame should leak when the stream is not in play"
    );
}

// The receive seam: a frame arriving on the reserved stream channel
// drains into the runtime as the ordinary blob frame it wraps, and
// handle_blob ingests it. The stream callback itself is exercised by the
// library; this proves the carrier's deframe → inbox → handle_blob hop.
// The chunk payload here is deliberately undecryptable — the routing is
// the assertion; attachment_runtime tests cover the crypto underneath.
#[test]
fn a_stream_delivered_chunk_reaches_handle_blob_through_the_carrier() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
    let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
    let invite = alice
        .create_invite(StartSessionRequest {
            display_name: "Alice".to_string(),
            listen_port: 42189,
            static_peer: None,
        })
        .expect("Alice invite should be created");
    let session = alice
        .sessions
        .get_mut(&invite.session_id)
        .expect("Alice session should exist");

    let chunk = BlobEnvelope::Chunk {
        participant_id: "peer-participant".to_string(),
        frame: crate::attachment_runtime::ChunkFrame {
            attachment_id: "att-stream-in".to_string(),
            chunk_index: 0,
            ciphertext_b64: crate::conversation::encode(b"not-a-real-chunk"),
        },
    };
    let envelope_bytes = serde_json::to_vec(&chunk).expect("chunk envelope should serialize");
    let framed = crate::stream_transport::frame_for_channel(&session.blob_channel, &envelope_bytes)
        .expect("the carrier should frame the envelope");

    // The stream callback files the framed payload under the reserved
    // channel; the runtime's drain must unwrap it before routing.
    let peer_id = "ab".repeat(32);
    let stream_message = MossReceivedMessage {
        channel: crate::stream_transport::stream_inbox_channel(&peer_id),
        payload: framed,
    };
    let routed = crate::stream_transport::passthrough_or_deframe(stream_message);
    assert_eq!(routed.channel, session.blob_channel);
    assert_eq!(
        routed.payload, envelope_bytes,
        "the envelope rides verbatim"
    );

    // handle_blob ingests (the transfer is unknown → swallowed) without
    // erroring: an undecryptable chunk fails the slot, not the drain.
    session
        .handle_moss_message(routed)
        .expect("a stream-delivered chunk must not error the drain");
}

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

// Builds a lone Alice session on `port` — enough to drive the session-level
// pumps and control handlers without a live counterpart.
fn lone_session(port: u16) -> (PrivateDmRuntime, String) {
    drain_received_messages();
    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
    let mut alice = PrivateDmRuntime::from_shared(runtime, temp_store(), None);
    let invite = alice
        .create_invite(StartSessionRequest {
            display_name: "Alice".to_string(),
            listen_port: port,
            static_peer: None,
        })
        .expect("Alice invite should be created");
    (alice, invite.session_id)
}

fn test_call_offer_json(session_id: &str, call_id: &str) -> Vec<u8> {
    serde_json::to_vec(&ControlEnvelope::CallOffer {
        session_id: session_id.to_string(),
        participant_id: "the-other-participant".to_string(),
        from_device: "Bob".to_string(),
        call_id: call_id.to_string(),
        // The already-answered branch returns before decrypting.
        offer_ciphertext_b64: "Y2lwaGVy".to_string(),
    })
    .expect("offer should serialize")
}

// Call regression: CallOffer was a one-shot publish, so a ring lost on a
// flapping link never repeated and the caller waited forever. The offer must
// repeat on the CALL_RESEND_MS cadence while the call is unanswered.
#[test]
fn caller_retransmits_the_call_offer_while_unanswered() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let (mut alice, session_id) = lone_session(42197);
    let session = alice
        .sessions
        .get_mut(&session_id)
        .expect("Alice session should exist");

    let mut call = CallState::outgoing("call-1".into(), "k".into(), "n".into(), String::new());
    call.mark_offer_sent(1_000);
    session.call = Some(call);

    session.pump_call_signaling(1_000 + CALL_RESEND_MS - 1);
    assert_eq!(
        session.call.as_ref().expect("call held").offer_last_ms,
        1_000,
        "a resend inside the throttle window is suppressed"
    );

    let due = 1_000 + CALL_RESEND_MS;
    session.pump_call_signaling(due);
    assert_eq!(
        session.call.as_ref().expect("call held").offer_last_ms,
        due,
        "the offer re-publishes once the cadence is due"
    );

    // Answered: the ring stops repeating.
    session
        .call
        .as_mut()
        .expect("call held")
        .become_active(due + 1);
    session.pump_call_signaling(due + CALL_RESEND_MS * 10);
    assert_eq!(
        session.call.as_ref().expect("call held").offer_last_ms,
        due,
        "an answered call stops re-offering"
    );
}

// The ring budget is measured from the FIRST offer, so retransmits cannot
// extend it indefinitely. Timing out logs the call as missed and clears it,
// which is what closes the caller's outgoing modal.
#[test]
fn caller_gives_up_once_the_ring_budget_is_spent() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let (mut alice, session_id) = lone_session(42198);
    let session = alice
        .sessions
        .get_mut(&session_id)
        .expect("Alice session should exist");

    let mut call = CallState::outgoing("call-2".into(), "k".into(), "n".into(), String::new());
    call.mark_offer_sent(1_000);
    call.mark_offer_sent(1_000 + CALL_RING_TIMEOUT_MS - 1);
    session.call = Some(call);

    session.pump_call_signaling(1_000 + CALL_RING_TIMEOUT_MS);
    assert!(
        session.call.is_none(),
        "the unanswered call is cleared once the budget is spent"
    );
    let logged = session
        .messages
        .iter()
        .filter_map(|message| message.call_event.as_ref())
        .find(|event| event.call_id == "call-2")
        .expect("the timed-out call is logged");
    assert_eq!(logged.kind, "missed");
}

// The heart of the bug: the callee answered, its CallAccept was dropped, and
// nothing ever re-sent it — the caller rang out against a peer already in an
// active call. A repeated offer for a call we hold as Active must re-answer.
#[test]
fn answered_callee_re_accepts_a_repeated_offer() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let (mut alice, session_id) = lone_session(42199);
    let session = alice
        .sessions
        .get_mut(&session_id)
        .expect("Alice session should exist");

    let mut call = CallState::ringing("call-3".into(), "k".into(), "n".into(), "Bob".into());
    call.become_active(1_000);
    session.call = Some(call);

    // Fail the next publish, so the error IS the observation that a
    // CallAccept went out.
    let _publish_fail = wire::fail_next_test_publish("observe the accept");
    let offer = test_call_offer_json(&session_id, "call-3");
    assert!(
        session.handle_control(offer.clone()).is_err(),
        "a repeated offer for an answered call re-sends the CallAccept"
    );
    assert_eq!(
        session.call.as_ref().expect("call held").phase,
        CallPhase::Active,
        "the repeat does not disturb the answered call"
    );

    // Still ringing (user has not picked up): nothing to re-answer yet.
    session.call.as_mut().expect("call held").phase = CallPhase::Ringing;
    assert!(
        session.handle_control(offer).is_ok(),
        "an unanswered ring must not auto-accept on the repeat"
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

// Voice media has its own queue, so the DM drain never carries it and the
// audio loop never waits on the DM runtime.
#[test]
fn voice_call_channels_are_claimed_by_the_media_queue_not_the_dm() {
    assert!(transport::is_private_dm_inbound("mls-control/session-one"));
    assert!(transport::is_private_dm_inbound("mls-data/session-one"));
    assert!(transport::is_private_dm_inbound("mls-blob/session-one"));
    assert!(!transport::is_private_dm_inbound("voice-call/call-one"));
    assert!(transport::is_call_media_inbound("voice-call/call-one"));
    assert!(!transport::is_call_media_inbound("mls-data/session-one"));
    assert!(!transport::is_private_dm_inbound("public-channel/general"));
}

// Real Moss call E2E. This exercises the voice-call subscription and
// frame routing path, but local peer handshakes are timing-sensitive in
// the full suite, so run it explicitly when touching call transport.
#[test]
#[ignore]
fn private_dm_runtime_routes_voice_call_frames_over_moss() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();
    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
    let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
    let invite = alice
        .create_invite(StartSessionRequest {
            display_name: "Alice".to_string(),
            listen_port: 42134,
            static_peer: None,
        })
        .expect("Alice invite should be created");

    let mut bob = PrivateDmRuntime::from_shared(runtime, temp_store(), None);
    bob.accept_invite(AcceptInviteRequest {
        invite_uri: invite.invite_uri.clone(),
        display_name: "Bob".to_string(),
        listen_port: 42135,
        static_peer: Some("127.0.0.1:42134".to_string()),
    })
    .expect("Bob should accept invite");

    wait_until_ready(&mut alice, &mut bob, &invite.session_id);
    let call = alice
        .call_start(&invite.session_id)
        .expect("Alice should start a call");
    wait_for_pending_call(&mut bob, &invite.session_id, &call.call_id);
    bob.call_accept(&invite.session_id, &call.call_id)
        .expect("Bob should accept the call");
    wait_for_active_call(&mut alice, &mut bob, &invite.session_id, &call.call_id);

    alice
        .call_media()
        .send(&call.call_id, &test_call_frame(0, &[1, 2, 3]))
        .expect("Alice should send a voice frame");
    assert_eq!(
        wait_for_call_frame(&bob, &call.call_id),
        test_call_frame(0, &[1, 2, 3])
    );

    bob.call_media()
        .send(&call.call_id, &test_call_frame(1 << 63, &[4, 5, 6]))
        .expect("Bob should send a voice frame");
    assert_eq!(
        wait_for_call_frame(&alice, &call.call_id),
        test_call_frame(1 << 63, &[4, 5, 6])
    );
}

// Heavy end-to-end transfer over real Moss. Loading the Moss Go runtime
// a third time in one process makes the handshake flaky under suite
// load, so this runs on demand via `cargo test -- --ignored`.
#[test]
#[ignore]
fn private_dm_runtime_transfers_attachment_over_moss() {
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

    let receiver_store = temp_store();
    let mut bob = PrivateDmRuntime::from_shared(runtime, Arc::clone(&receiver_store), None);
    bob.accept_invite(AcceptInviteRequest {
        invite_uri: invite.invite_uri.clone(),
        display_name: "Bob".to_string(),
        listen_port: 42133,
        static_peer: Some("127.0.0.1:42132".to_string()),
    })
    .expect("Bob should accept invite");

    wait_until_ready(&mut alice, &mut bob, &invite.session_id);

    let payload: Vec<u8> = (0..(CHUNK_SIZE as usize) * 2 + 123)
        .map(|index| (index % 251) as u8)
        .collect();
    let send = alice
        .send_attachment(
            &invite.session_id,
            "photo.bin".to_string(),
            "application/octet-stream".to_string(),
            payload.clone(),
            None,
            None,
        )
        .expect("Alice should send attachment");

    let attachment_id = wait_for_attachment(&mut bob, &invite.session_id, &send.attachment_id);
    bob.download_attachment(&invite.session_id, &attachment_id)
        .expect("Bob should start download");

    wait_for_attachment_available(&mut alice, &mut bob, &invite.session_id, &attachment_id);
    let stored = receiver_store
        .read_blob(&send.content_hash, "photo.bin")
        .expect("Bob should have stored the blob");
    assert_eq!(stored, payload);
}

fn wait_for_attachment(
    runtime: &mut PrivateDmRuntime,
    session_id: &str,
    attachment_id: &str,
) -> String {
    for _ in 0..40 {
        let snapshot = runtime.poll_session(session_id).expect("poll should pass");
        if snapshot
            .attachments
            .iter()
            .any(|view| view.attachment_id == attachment_id)
        {
            return attachment_id.to_string();
        }
        std::thread::sleep(std::time::Duration::from_millis(100));
    }
    panic!("attachment manifest did not arrive");
}

fn wait_for_attachment_available(
    alice: &mut PrivateDmRuntime,
    bob: &mut PrivateDmRuntime,
    session_id: &str,
    attachment_id: &str,
) {
    for _ in 0..120 {
        let _ = alice.poll_session(session_id);
        let snapshot = bob.poll_session(session_id).expect("poll should pass");
        if snapshot.attachments.iter().any(|view| {
            view.attachment_id == attachment_id && view.state == AttachmentState::Available
        }) {
            return;
        }
        std::thread::sleep(std::time::Duration::from_millis(100));
    }
    panic!("attachment did not finish downloading");
}

fn wait_until_ready(alice: &mut PrivateDmRuntime, bob: &mut PrivateDmRuntime, session_id: &str) {
    // The Moss handshake is timing-sensitive; allow generous headroom so
    // the test stays green under full-suite CPU contention.
    for _ in 0..200 {
        let alice_ready = alice
            .poll_session(session_id)
            .expect("Alice poll should pass")
            .state
            == DmSessionState::Connected;
        let bob_ready = bob
            .poll_session(session_id)
            .expect("Bob poll should pass")
            .state
            == DmSessionState::Connected;
        if alice_ready && bob_ready {
            return;
        }
        std::thread::sleep(std::time::Duration::from_millis(100));
    }

    panic!("sessions did not become ready");
}

fn wait_for_pending_call(runtime: &mut PrivateDmRuntime, session_id: &str, call_id: &str) {
    for _ in 0..60 {
        let snapshot = runtime.poll_session(session_id).expect("poll should pass");
        if snapshot
            .pending_call
            .as_ref()
            .is_some_and(|call| call.call_id == call_id)
        {
            return;
        }
        std::thread::sleep(std::time::Duration::from_millis(100));
    }
    panic!("pending call did not arrive");
}

fn wait_for_active_call(
    alice: &mut PrivateDmRuntime,
    bob: &mut PrivateDmRuntime,
    session_id: &str,
    call_id: &str,
) {
    for _ in 0..60 {
        let alice_active = alice
            .poll_session(session_id)
            .expect("Alice poll should pass")
            .active_call
            .as_ref()
            .is_some_and(|call| call.call_id == call_id);
        let bob_active = bob
            .poll_session(session_id)
            .expect("Bob poll should pass")
            .active_call
            .as_ref()
            .is_some_and(|call| call.call_id == call_id);
        if alice_active && bob_active {
            return;
        }
        std::thread::sleep(std::time::Duration::from_millis(100));
    }
    panic!("call did not become active");
}

fn wait_for_call_frame(runtime: &PrivateDmRuntime, call_id: &str) -> Vec<u8> {
    for _ in 0..60 {
        let frames = runtime.call_media().drain(call_id);
        if let Some(frame) = frames.into_iter().next() {
            return frame;
        }
        std::thread::sleep(std::time::Duration::from_millis(100));
    }
    panic!("voice frame did not arrive");
}

fn test_call_frame(seq: u64, payload: &[u8]) -> Vec<u8> {
    let mut frame = seq.to_be_bytes().to_vec();
    frame.extend_from_slice(payload);
    frame
}

fn wait_for_message(
    runtime: &mut PrivateDmRuntime,
    session_id: &str,
    body: &str,
) -> SessionSnapshot {
    for _ in 0..30 {
        let snapshot = runtime.poll_session(session_id).expect("poll should pass");
        if snapshot.messages.iter().any(|message| message.body == body) {
            return snapshot;
        }
        std::thread::sleep(std::time::Duration::from_millis(100));
    }

    panic!("message did not arrive");
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
