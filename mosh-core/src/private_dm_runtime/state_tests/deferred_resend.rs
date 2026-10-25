use super::*;

#[test]
fn contact_delivery_is_not_downgraded_when_a_sibling_retry_remains() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    let sent = alice
        .send_message(&invite.session_id, "already delivered".into())
        .unwrap();
    let session = alice.session_mut(&invite.session_id).unwrap();
    // Linked DMs retain a Sent attempt for an offline sibling after the
    // contact receipt has already marked the visible row Delivered.
    session.state = DmSessionState::Handshaking;
    session
        .messages
        .mark_delivery(&sent.message_id, MessageDeliveryStatus::Delivered, None, 0)
        .unwrap();
    session
        .outbound_attempts
        .get_mut(&sent.message_id)
        .unwrap()
        .auto_resends = AUTO_RESEND_MAX;
    net.drop_frames(BOB_ID, ALICE_ID, |_, payload| {
        payload_says(payload, "DeliveryAck")
    });
    bob.send_message(&invite.session_id, "new contact proof".into())
        .unwrap();
    let snapshot = alice.poll_session(&invite.session_id).unwrap();
    assert_eq!(
        snapshot
            .messages
            .iter()
            .find(|message| message.message_id.as_deref() == Some(&sent.message_id))
            .unwrap()
            .delivery_status,
        Some(MessageDeliveryStatus::Delivered)
    );
}

#[test]
fn fresh_contact_proof_requeues_exhausted_text_without_duplicating_history() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    net.endpoint(ALICE_ID).drain();
    net.drop_frames(ALICE_ID, BOB_ID, |_, _| true);
    let sent = alice
        .send_message(&invite.session_id, "lost before recovery".into())
        .unwrap();
    let start = now_ms();
    for index in 1..=AUTO_RESEND_MAX {
        alice.drain_inbound_at(start + u64::from(index) * AUTO_RESEND_MS);
    }
    assert_eq!(
        alice
            .session_ref(&invite.session_id)
            .unwrap()
            .outbound_attempts[&sent.message_id]
            .auto_resends,
        AUTO_RESEND_MAX
    );
    let resumed = start + u64::from(AUTO_RESEND_MAX + 1) * AUTO_RESEND_MS;
    net.drop_frames(ALICE_ID, BOB_ID, |_, _| false);
    alice.drain_inbound_at(resumed);
    assert!(
        bob.poll_session(&invite.session_id)
            .unwrap()
            .messages
            .is_empty(),
        "elapsed time or a transport path alone must not reset the retry budget"
    );
    bob.send_message(&invite.session_id, "authenticated contact proof".into())
        .unwrap();
    alice.drain_inbound_at(resumed);
    let received = bob.poll_session(&invite.session_id).unwrap();
    assert_eq!(
        received
            .messages
            .iter()
            .filter(|message| message.body == "lost before recovery")
            .count(),
        1
    );
    let received = bob.poll_session(&invite.session_id).unwrap();
    assert_eq!(
        received
            .messages
            .iter()
            .filter(|message| message.body == "lost before recovery")
            .count(),
        1
    );
    assert!(alice
        .poll_session(&invite.session_id)
        .unwrap()
        .messages
        .iter()
        .any(
            |message| message.message_id.as_deref() == Some(sent.message_id.as_str())
                && message.delivery_status == Some(MessageDeliveryStatus::Delivered)
        ));
}

#[test]
fn unrelated_contact_traffic_does_not_restart_exhausted_sends() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    net.drop_frames(ALICE_ID, BOB_ID, |_, payload| {
        payload_says(payload, "\"message_id\"")
    });
    let sent = alice
        .send_message(&invite.session_id, "lost until recovery".into())
        .unwrap();
    alice
        .session_mut(&invite.session_id)
        .unwrap()
        .outbound_attempts
        .get_mut(&sent.message_id)
        .unwrap()
        .auto_resends = AUTO_RESEND_MAX;
    for _ in 0..3 {
        bob.send_message(&invite.session_id, "unrelated incoming text".into())
            .unwrap();
        alice.poll_session(&invite.session_id).unwrap();
        let session = alice.session_ref(&invite.session_id).unwrap();
        assert_eq!(session.state, DmSessionState::Connected);
        assert_eq!(
            session.outbound_attempts[&sent.message_id].auto_resends, AUTO_RESEND_MAX,
            "a connected peer's unrelated traffic cannot renew a delivery budget"
        );
    }
}

#[test]
fn a_new_delivery_receipt_recovers_lost_text_on_a_connected_session() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    net.drop_frames(ALICE_ID, BOB_ID, |_, _| true);
    let sent = alice
        .send_message(&invite.session_id, "older lost text".into())
        .unwrap();
    alice
        .session_mut(&invite.session_id)
        .unwrap()
        .outbound_attempts
        .get_mut(&sent.message_id)
        .unwrap()
        .auto_resends = AUTO_RESEND_MAX;
    net.drop_frames(ALICE_ID, BOB_ID, |_, _| false);
    alice
        .send_message(&invite.session_id, "new outgoing text".into())
        .unwrap();
    bob.poll_session(&invite.session_id).unwrap();
    alice.poll_session(&invite.session_id).unwrap();
    assert_eq!(
        bob.poll_session(&invite.session_id)
            .unwrap()
            .messages
            .iter()
            .filter(|message| message.body == "older lost text")
            .count(),
        1
    );
    assert_eq!(
        alice_message(&mut alice, &invite.session_id, &sent.message_id).delivery_status,
        Some(MessageDeliveryStatus::Delivered)
    );
}

#[test]
fn a_normal_receipt_does_not_republish_an_active_outgoing_batch() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    net.drop_frames(ALICE_ID, BOB_ID, |_, _| true);
    alice
        .send_message(&invite.session_id, "still in flight".into())
        .unwrap();
    net.drop_frames(ALICE_ID, BOB_ID, |_, _| false);
    alice
        .send_message(&invite.session_id, "confirmed".into())
        .unwrap();
    bob.poll_session(&invite.session_id).unwrap();
    alice.poll_session(&invite.session_id).unwrap();
    let snapshot = bob.poll_session(&invite.session_id).unwrap();
    assert_eq!(
        snapshot.messages.len(),
        1,
        "ordinary receipts must not republish a batch before its retry deadline"
    );
    assert_eq!(snapshot.messages[0].body, "confirmed");
}

#[test]
fn an_inflight_sibling_retry_does_not_downgrade_contact_delivery() {
    let (_net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    let sent = alice
        .send_message(&invite.session_id, "delivered to contact".into())
        .unwrap();
    let session = alice.session_mut(&invite.session_id).unwrap();
    session
        .messages
        .mark_delivery(&sent.message_id, MessageDeliveryStatus::Delivered, None, 0)
        .unwrap();
    session
        .outbound_attempts
        .get_mut(&sent.message_id)
        .unwrap()
        .last_send_ms = 0;
    assert!(session
        .pump_unacked_resends(now_ms())
        .contains(&sent.message_id));
    assert_eq!(
        session
            .messages
            .iter()
            .find(|message| message.message_id.as_deref() == Some(&sent.message_id))
            .unwrap()
            .delivery_status,
        Some(MessageDeliveryStatus::Delivered)
    );
}

#[test]
fn refused_retries_throttle_crypto_without_spending_publication_budget() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    let sent = alice
        .send_message(&invite.session_id, "retry later".into())
        .unwrap();
    net.fail_publishes(ALICE_ID, true);
    let session = alice.session_mut(&invite.session_id).unwrap();
    let start = session.outbound_attempts[&sent.message_id].last_send_ms + AUTO_RESEND_MS;
    session.pump_unacked_resends(start);
    let after_refusal = session.crypto.snapshot();
    session.pump_unacked_resends(start + 1);
    assert_eq!(
        session.crypto.snapshot(),
        after_refusal,
        "a refused retry must not derive fresh ciphertext on each service tick"
    );
    assert_eq!(session.outbound_attempts[&sent.message_id].auto_resends, 0);
    net.fail_publishes(ALICE_ID, false);
    assert!(session
        .pump_unacked_resends(start + AUTO_RESEND_MS)
        .contains(&sent.message_id));
    assert_eq!(session.outbound_attempts[&sent.message_id].auto_resends, 1);
}
