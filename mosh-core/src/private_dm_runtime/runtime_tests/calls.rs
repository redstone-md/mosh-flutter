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

    let mut call = CallState::outgoing("call-1".into(), String::new());
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

    let mut call = CallState::outgoing("call-2".into(), String::new());
    call.mark_offer_sent(1_000);
    call.mark_offer_sent(30_999);
    session.call = Some(call);

    session.pump_call_signaling(31_000);
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

#[test]
fn incoming_native_ring_expires_without_flutter_or_a_deadline_extension() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let (mut runtime, id) = lone_session(0);
    let session = runtime.sessions.get_mut(&id).unwrap();
    let mut call = CallState::ringing("incoming".into(), "Alice".into());
    call.mark_offer_sent(1_000);
    call.mark_offer_sent(30_999);
    session.call = Some(call);
    session.pump_call_signaling(30_999);
    assert!(session.call.is_some());
    session.pump_call_signaling(31_000);
    assert!(session.call.is_none());
    let event = session
        .messages
        .iter()
        .find_map(|message| message.call_event.as_ref())
        .unwrap();
    assert_eq!(event.call_id, "incoming");
    assert_eq!(event.kind, "missed");
}
