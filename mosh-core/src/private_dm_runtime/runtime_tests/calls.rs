use super::*;

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
