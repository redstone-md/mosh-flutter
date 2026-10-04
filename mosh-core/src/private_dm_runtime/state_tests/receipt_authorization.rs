use super::*;

#[test]
fn receipt_cleanup_uses_the_effective_app_directory() {
    let status = std::process::Command::new(std::env::current_exe().unwrap())
        .args([
            "--exact",
            "private_dm_runtime::state_tests::receipt_authorization::receipt_directory_process",
            "--ignored",
            "--nocapture",
        ])
        .status()
        .unwrap();
    assert!(status.success());
}

#[test]
#[ignore = "Isolated startup state worker invoked by the receipt fixture regression."]
fn receipt_directory_process() {
    let _guard = crate::moss_ffi::MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let prior = crate::test_temp_directory::TempDirectory::new("mosh-receipts-prior-app-dir");
    crate::api::shared_runtime::set_app_data_dir(prior.path().to_string_lossy().into_owned())
        .unwrap();
    let (_, mut runtime, _) = memory_pair();
    runtime.set_read_receipts_enabled(true).unwrap();
    assert!(runtime.read_receipts_enabled());
    let dir = point_data_dir_once();
    clear_toggle(&dir);
    assert!(
        !runtime.read_receipts_enabled(),
        "cleanup must clear the active setting even when a different app directory was injected first"
    );
    assert_eq!(dir, prior.path().join("mosh"));
}

// A relayed counterpart is reachable too, and the snapshot says how.

#[test]
fn a_message_settles_from_sent_to_delivered_to_read() {
    let _guard = crate::moss_ffi::MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let dir = point_data_dir_once();
    clear_toggle(&dir);
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);

    // Toggle ON for both sides — the symmetric pair this feature assumes.
    alice
        .set_read_receipts_enabled(true)
        .expect("Alice should store the toggle");
    bob.set_read_receipts_enabled(true)
        .expect("Bob should store the toggle");
    assert!(alice.read_receipts_enabled());
    assert!(bob.read_receipts_enabled());

    let sent = alice
        .send_message(&invite.session_id, "the settlement".to_string())
        .expect("Alice should send");
    assert_eq!(sent.delivery_status, MessageDeliveryStatus::Sent);

    // Bob drains: the message lands and his runtime acks it (Delivered).
    bob.drain_inbound();
    let view = bob
        .poll_session(&invite.session_id)
        .expect("Bob poll should pass");
    assert_eq!(view.messages.len(), 1, "Bob holds the message");

    // Bob opens the conversation: the receipt frame goes out.
    crate::moss_ffi::clear_event_log();
    bob.mark_viewed(&invite.session_id)
        .expect("Bob viewing should pass");
    assert!(
        read_events(&invite.session_id)
            .iter()
            .any(|detail| detail.contains("self-read")),
        "the receiver files its honest self-read event"
    );

    // The receipt reaches Alice: her snapshot marks the message read.
    deliver_inbox(&net, ALICE_ID, BOB_ID, &invite);
    alice.drain_inbound();
    let message = alice_message(&mut alice, &invite.session_id, &sent.message_id);
    assert_eq!(
        message.read,
        Some(true),
        "the sender's ticks learn the color: read"
    );
    assert!(
        read_events(&invite.session_id)
            .iter()
            .any(|detail| detail.contains("peer-read")),
        "the sender files the peer-read event into the ring"
    );

    // Idempotence: the same receipt replayed changes nothing further.
    deliver_inbox(&net, ALICE_ID, BOB_ID, &invite);
    let before = read_events(&invite.session_id).len();
    alice.drain_inbound();
    assert_eq!(
        read_events(&invite.session_id).len(),
        before,
        "a duplicate receipt files no second event"
    );

    clear_toggle(&dir);
}

// A toggle that is off makes mark_viewed a no-op: no frame on the wire, no
// event filed — and the message the peer later receipts is ignored too
// (symmetry: a user who does not send receipts does not see others').
#[test]
fn a_disabled_toggle_sends_nothing_and_ignores_inbound_receipts() {
    let _guard = crate::moss_ffi::MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let dir = point_data_dir_once();
    clear_toggle(&dir);
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);

    // Default is off — nothing was ever written.
    assert!(!bob.read_receipts_enabled(), "the default is off");

    let sent = alice
        .send_message(&invite.session_id, "read me not".to_string())
        .expect("Alice should send");
    bob.drain_inbound();

    // Bob's poll marks the screen open, but his toggle is off.
    crate::moss_ffi::clear_event_log();
    bob.mark_viewed(&invite.session_id)
        .expect("viewing should pass");
    assert_eq!(
        receipt_frames(&net, ALICE_ID),
        0,
        "an off toggle sends nothing"
    );
    assert!(
        read_events(&invite.session_id).is_empty(),
        "an off toggle files no events"
    );

    // The setting is app-wide. Stage a genuine receipt while enabled, then
    // turn it off before the receiving runtime drains that receipt.
    alice.set_read_receipts_enabled(true).expect("toggle on");
    bob.mark_viewed(&invite.session_id)
        .expect("receipt goes out");
    let receipt = net
        .endpoint(ALICE_ID)
        .drain()
        .into_iter()
        .find(|frame| payload_says(&frame.payload, "ReadReceipt"))
        .expect("a genuine encrypted receipt must reach Alice");
    alice.set_read_receipts_enabled(false).expect("toggle off");
    assert!(!alice.read_receipts_enabled());
    crate::moss_ffi::clear_event_log();
    publish_control_from(&net, &invite, BOB_ID, ALICE_ID, &receipt.payload);
    alice.drain_inbound();
    assert_eq!(
        alice_message(&mut alice, &invite.session_id, &sent.message_id).read,
        None,
        "the disabled receiver ignores a delivered, authentic receipt"
    );
    assert!(read_events(&invite.session_id).is_empty());

    // The very same ciphertext succeeds when enabled: rejection above came
    // from the setting, and did not consume its MLS receive generation.
    alice.set_read_receipts_enabled(true).expect("toggle on");
    publish_control_from(&net, &invite, BOB_ID, ALICE_ID, &receipt.payload);
    alice.drain_inbound();
    assert_eq!(
        alice_message(&mut alice, &invite.session_id, &sent.message_id).read,
        Some(true),
        "the enabled receiver accepts that authentic receipt"
    );

    clear_toggle(&dir);
}

// A receipt is only as good as its MLS decrypt: a garbage ciphertext and a
// ciphertext minted by the receiving member (MLS cannot decrypt own
// messages) both die before touching the ticks — the DeliveryAck forgery
// pattern, replayed against receipts.
#[test]
fn a_forged_receipt_never_colors_a_message() {
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

    let sent = alice
        .send_message(&invite.session_id, "forgery bait".to_string())
        .expect("Alice should send");
    bob.drain_inbound();

    crate::moss_ffi::clear_event_log();
    let participant_id = bob.sessions[&invite.session_id].participant_id.clone();

    // Forgery #1: garbage ciphertext.
    let forged = serde_json::to_vec(&ControlEnvelope::ReadReceipt {
        session_id: invite.session_id.clone(),
        participant_id: participant_id.clone(),
        receipt_ciphertext_b64: encode(b"not-an-mls-ciphertext"),
    })
    .expect("forged envelope should serialize");
    publish_control_from(&net, &invite, BOB_ID, ALICE_ID, &forged);
    alice.drain_inbound();
    assert_eq!(
        alice_message(&mut alice, &invite.session_id, &sent.message_id).read,
        None
    );

    // Forgery #2: Alice's own ciphertext replayed toward Alice while the
    // envelope claims Bob. MLS must reject the receiving member's own frame.
    let self_minted = {
        let session = alice
            .sessions
            .get_mut(&invite.session_id)
            .expect("Alice session should exist");
        let body = ReadReceiptBody {
            message_id: sent.message_id.clone(),
        };
        let ciphertext = session
            .crypto
            .encrypt(&serde_json::to_vec(&body).expect("body should serialize"))
            .expect("Alice should encrypt");
        serde_json::to_vec(&ControlEnvelope::ReadReceipt {
            session_id: invite.session_id.clone(),
            participant_id,
            receipt_ciphertext_b64: encode(&ciphertext),
        })
        .expect("self-minted envelope should serialize")
    };
    publish_control_from(&net, &invite, BOB_ID, ALICE_ID, &self_minted);

    alice.drain_inbound();
    assert_eq!(
        alice_message(&mut alice, &invite.session_id, &sent.message_id).read,
        None
    );
    assert!(
        read_events(&invite.session_id).is_empty(),
        "no forged receipt files an event"
    );

    // Now the honest path over the same link, to prove the forgeries were the
    // problem and not the plumbing: both forgeries have already drained;
    // Bob's genuine receipt now colors Alice's message over the same link.
    bob.mark_viewed(&invite.session_id).expect("viewing passes");
    alice.drain_inbound();
    assert_eq!(
        alice_message(&mut alice, &invite.session_id, &sent.message_id).read,
        Some(true),
        "the forged attempt did not break the honest path"
    );

    clear_toggle(&dir);
}

// The encrypted body is a JSON object, never the raw id: a bystander reading
// the control wire learns nothing (the id never appears in the clear).
#[test]
fn a_receipt_travels_encrypted_per_message() {
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
        .send_message(&invite.session_id, "secret payload".to_string())
        .expect("Alice should send");
    bob.drain_inbound();

    bob.mark_viewed(&invite.session_id).expect("viewing passes");
    let frame = net
        .endpoint(ALICE_ID)
        .drain()
        .into_iter()
        .find(|frame| payload_says(&frame.payload, "ReadReceipt"))
        .expect("one receipt frame should be on the wire");
    assert!(
        !payload_says(&frame.payload, &sent.message_id),
        "the receipted id travels encrypted, never in the clear"
    );

    // Two unread messages produce two frames: one id per frame, the ack shape.
    let second = alice
        .send_message(&invite.session_id, "second unread".to_string())
        .expect("Alice should send");
    bob.drain_inbound();
    bob.mark_viewed(&invite.session_id).expect("viewing passes");
    let frames = net
        .endpoint(ALICE_ID)
        .drain()
        .into_iter()
        .filter(|frame| payload_says(&frame.payload, "ReadReceipt"))
        .count();
    assert_eq!(frames, 1, "only the NEW message receipts again");
    assert!(
        !payload_says(
            &(net
                .endpoint(BOB_ID)
                .drain()
                .first()
                .map(|f| f.payload.clone())
                .unwrap_or_default()),
            &second.message_id
        ),
        "no id in the clear"
    );

    clear_toggle(&dir);
}
