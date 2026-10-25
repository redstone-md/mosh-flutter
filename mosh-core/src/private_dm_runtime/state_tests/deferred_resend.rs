use super::*;

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
