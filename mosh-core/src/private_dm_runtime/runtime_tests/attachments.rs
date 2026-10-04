use super::*;

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
