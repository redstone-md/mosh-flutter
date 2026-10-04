use super::*;

// Read state survives a restart: a receipt Bob already told Alice about is
// remembered when her runtime reopens on the same store — no re-ask, and the
// snapshot still colors the message.
#[test]
fn read_state_survives_a_restart() {
    let _guard = crate::moss_ffi::MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let dir = point_data_dir_once();
    clear_toggle(&dir);

    let mut db_path: std::path::PathBuf = std::env::temp_dir();
    db_path.push(format!("mosh-receipts-restart-{}.redb", std::process::id()));
    let _ = std::fs::remove_file(&db_path);
    let persistence = Arc::new(
        crate::persistence::Persistence::open_with_dek(&db_path, [7u8; 32])
            .expect("store should open"),
    );

    let net = MemoryNet::new();
    net.link_both(ALICE_ID, BOB_ID, PeerTransport::Direct);
    let mut alice = PrivateDmRuntime::with_transport(
        net.endpoint(ALICE_ID),
        temp_store(),
        Some(persistence.clone()),
    );
    // Bob runs WITHOUT persistence: only the runtime being restarted (Alice's)
    // owns rows in this store. Two peers sharing one store would overwrite each
    // other's record and MLS-snapshot rows — they are keyed by session id.
    let mut bob = PrivateDmRuntime::with_transport(net.endpoint(BOB_ID), temp_store(), None);
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    bob.set_read_receipts_enabled(true).expect("toggle on");

    let sent = alice
        .send_attachment(
            &invite.session_id,
            "report.pdf".to_string(),
            "application/pdf".to_string(),
            vec![7; 1024],
            None,
            None,
        )
        .expect("Alice should send");
    let message_id = alice
        .poll_session(&invite.session_id)
        .expect("Alice snapshot")
        .messages
        .into_iter()
        .find(|message| {
            message
                .attachment
                .as_ref()
                .is_some_and(|attachment| attachment.attachment_id == sent.attachment_id)
        })
        .and_then(|message| message.message_id)
        .expect("attachment row id");
    bob.drain_inbound();
    bob.mark_viewed(&invite.session_id).expect("viewing passes");
    deliver_inbox(&net, ALICE_ID, BOB_ID, &invite);
    alice.drain_inbound();
    assert_eq!(
        alice_message(&mut alice, &invite.session_id, &message_id).read,
        Some(true),
        "the settlement completes before the restart"
    );
    // Persist the read state: the record write rides the tail pump.
    alice.tick(now_ms());

    // The restart: a NEW runtime on the SAME store, no connection to Bob.
    let mut revived = PrivateDmRuntime::with_transport(
        net.endpoint(ALICE_ID),
        temp_store(),
        Some(persistence.clone()),
    );
    revived.rehydrate();
    let listing = revived.list_sessions().expect("listing should pass");
    let view = listing
        .sessions
        .iter()
        .find(|session| session.session_id == invite.session_id)
        .expect("the session should rehydrate");
    let message = view
        .messages
        .iter()
        .find(|message| message.message_id.as_deref() == Some(message_id.as_str()))
        .expect("the message should rehydrate");
    assert_eq!(
        message.read,
        Some(true),
        "read state survives the restart without re-asking Bob"
    );

    let _ = std::fs::remove_file(&db_path);
    clear_toggle(&dir);
}

// An old counterpart client fails to decode the unknown ReadReceipt variant
// and drops the frame — pinned by the same drain-drop shape as typing's test.
#[test]
fn a_receipt_from_a_newer_client_decode_drops() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);

    let future = serde_json::json!({
        "type": "ReadReceiptV2",
        "session_id": invite.session_id,
        "participant_id": "peer-participant",
        "receipt_ciphertext_b64": encode(b"whatever"),
    });
    let bytes = serde_json::to_vec(&future).expect("future envelope should serialize");
    assert!(
        decode_json::<ControlEnvelope>(&bytes).is_err(),
        "an unknown variant name must fail decode"
    );
    publish_control_from(&net, &invite, ALICE_ID, BOB_ID, &bytes);
    bob.drain_inbound();
    let _ = alice;
}

// A receipt the transport refused must not be recorded as sent: the next
// `mark_viewed` re-sends it, or the counterpart never learns the message
// was read. The failed publish used to file the self-read event and pin the
// id anyway, so the receipt was lost with no retry path.
#[test]
fn a_refused_receipt_is_resent_on_the_next_viewed() {
    let _guard = crate::moss_ffi::MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let dir = point_data_dir_once();
    clear_toggle(&dir);
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);

    alice.set_read_receipts_enabled(true).expect("toggle on");
    bob.set_read_receipts_enabled(true).expect("toggle on");
    let sent = alice
        .send_message(&invite.session_id, "receipt me twice".to_string())
        .expect("Alice should send");
    bob.drain_inbound();

    // Bob's transport fails the receipt publish (a hard fault, not the soft
    // no-peers refusal).
    net.fail_publishes(BOB_ID, true);
    bob.mark_viewed(&invite.session_id)
        .expect("viewing passes even when the receipt fails");
    assert_eq!(
        receipt_frames(&net, ALICE_ID),
        0,
        "the failed publish put nothing on the wire"
    );
    assert!(
        read_events(&invite.session_id)
            .iter()
            .all(|detail| !detail.contains("self-read")),
        "a receipt that never left must not be logged as sent"
    );

    // The transport heals: the next mark_viewed must RE-send the receipt.
    net.fail_publishes(BOB_ID, false);
    bob.mark_viewed(&invite.session_id).expect("viewing passes");
    // Count what left Bob, then hand exactly those frames to Alice the way
    // the net would (a drain here would otherwise swallow them).
    let wire = net.endpoint(ALICE_ID).drain();
    let receipts = wire
        .iter()
        .filter(|frame| payload_says(&frame.payload, "ReadReceipt"))
        .count();
    assert_eq!(
        receipts, 1,
        "the recovered transport carries the re-sent receipt"
    );
    for frame in &wire {
        net.endpoint(BOB_ID)
            .publish(&invite.mesh_id, &frame.channel, &frame.payload)
            .expect("replay of an observed frame is a publish");
    }
    alice.drain_inbound();
    assert_eq!(
        alice_message(&mut alice, &invite.session_id, &sent.message_id).read,
        Some(true),
        "the re-sent receipt settles the read"
    );

    clear_toggle(&dir);
}
