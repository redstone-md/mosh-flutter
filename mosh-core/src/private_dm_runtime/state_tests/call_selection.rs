use super::*;

#[test]
fn answering_waits_for_the_callers_device_confirmation_before_media() {
    let (_net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    let call = alice.call_start(&invite.session_id).expect("start");
    bob.poll_session(&invite.session_id).expect("ring");

    bob.call_accept(&invite.session_id, &call.call_id)
        .expect("request answer");
    let waiting = bob.poll_session(&invite.session_id).expect("waiting");
    assert!(waiting.active_call.is_none(), "an answer is not selection");
    assert!(waiting.pending_call.is_some(), "retain the pending call");
    assert!(waiting.pending_call.expect("pending answer").answer_pending);
    bob.call_media()
        .send(&call.call_id, &[0; 24])
        .expect("unconfirmed media is ignored");
    assert!(alice.call_media().drain(&call.call_id).is_empty());

    let caller = alice.poll_session(&invite.session_id).expect("confirm");
    assert!(caller.active_call.is_some());
    let receiver = bob.poll_session(&invite.session_id).expect("selected");
    assert!(receiver.active_call.is_some());
}

#[test]
fn simultaneous_cross_calls_converge_before_media_starts() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    net.drop_frames(ALICE_ID, BOB_ID, |_, payload| {
        payload_says(payload, "CallControl")
    });
    net.drop_frames(BOB_ID, ALICE_ID, |_, payload| {
        payload_says(payload, "CallControl")
    });
    alice.call_start(&invite.session_id).expect("Alice calls");
    bob.call_start(&invite.session_id).expect("Bob calls");
    net.drop_frames(ALICE_ID, BOB_ID, |_, _| false);
    net.drop_frames(BOB_ID, ALICE_ID, |_, _| false);
    let at = now_ms() + CALL_RESEND_MS + 1;
    alice.drain_inbound_at(at);
    bob.drain_inbound_at(at);
    for _ in 0..4 {
        alice.service();
        bob.service();
    }
    let left = alice
        .poll_session(&invite.session_id)
        .expect("Alice view")
        .active_call
        .expect("Alice active");
    let right = bob
        .poll_session(&invite.session_id)
        .expect("Bob view")
        .active_call
        .expect("Bob active");
    assert_eq!(left.call_id, right.call_id);
    assert_ne!(left.direction, right.direction);
}

#[test]
fn cancellation_from_the_displayed_cross_call_ends_the_merged_call() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    net.drop_frames(ALICE_ID, BOB_ID, |_, payload| {
        payload_says(payload, "CallControl")
    });
    net.drop_frames(BOB_ID, ALICE_ID, |_, payload| {
        payload_says(payload, "CallControl")
    });
    let alice_call = alice.call_start(&invite.session_id).expect("Alice calls");
    let bob_call = bob.call_start(&invite.session_id).expect("Bob calls");
    net.drop_frames(ALICE_ID, BOB_ID, |_, _| false);
    net.drop_frames(BOB_ID, ALICE_ID, |_, _| false);
    let at = now_ms() + CALL_RESEND_MS + 1;
    alice.drain_inbound_at(at);
    bob.drain_inbound_at(at);
    for _ in 0..4 {
        alice.service();
        bob.service();
    }
    let canonical = alice
        .poll_session(&invite.session_id)
        .expect("selected")
        .active_call
        .expect("active");
    if canonical.call_id == alice_call.call_id {
        assert_eq!(
            bob.poll_session(&invite.session_id)
                .unwrap()
                .active_call
                .unwrap()
                .superseded_call_id
                .as_deref(),
            Some(bob_call.call_id.as_str())
        );
        bob.call_end(&invite.session_id, &bob_call.call_id, "cancel")
            .expect("cancel displayed Bob call");
    } else {
        assert_eq!(
            canonical.superseded_call_id.as_deref(),
            Some(alice_call.call_id.as_str())
        );
        alice
            .call_end(&invite.session_id, &alice_call.call_id, "cancel")
            .expect("cancel displayed Alice call");
    }
    for _ in 0..3 {
        alice.service();
        bob.service();
    }
    assert!(alice
        .poll_session(&invite.session_id)
        .expect("Alice ended")
        .active_call
        .is_none());
    assert!(bob
        .poll_session(&invite.session_id)
        .expect("Bob ended")
        .active_call
        .is_none());
}

#[test]
fn a_lost_end_is_retried_without_restarting_media() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    let call = alice.call_start(&invite.session_id).expect("start");
    bob.poll_session(&invite.session_id).expect("ring");
    bob.call_accept(&invite.session_id, &call.call_id)
        .expect("answer");
    alice.poll_session(&invite.session_id).expect("confirm");
    bob.poll_session(&invite.session_id).expect("selected");
    net.drop_frames(ALICE_ID, BOB_ID, |_, payload| {
        payload_says(payload, "CallControl")
    });
    alice
        .call_end(&invite.session_id, &call.call_id, "hangup")
        .expect("end locally");
    assert!(bob
        .poll_session(&invite.session_id)
        .expect("end lost")
        .active_call
        .is_some());
    net.drop_frames(ALICE_ID, BOB_ID, |_, _| false);
    alice.drain_inbound_at(now_ms() + CALL_RESEND_MS + 1);
    assert!(bob
        .poll_session(&invite.session_id)
        .expect("end retried")
        .active_call
        .is_none());
    assert!(alice
        .poll_session(&invite.session_id)
        .expect("stays ended")
        .active_call
        .is_none());
}

#[test]
fn a_lost_selection_keeps_the_receiver_pending_until_a_fresh_confirmation() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    let call = alice.call_start(&invite.session_id).expect("start");
    bob.poll_session(&invite.session_id).expect("ring");
    bob.call_accept(&invite.session_id, &call.call_id)
        .expect("answer");
    net.drop_frames(ALICE_ID, BOB_ID, |_, payload| {
        payload_says(payload, "CallControl")
    });
    assert!(alice
        .poll_session(&invite.session_id)
        .expect("select")
        .active_call
        .is_some());
    let pending = bob
        .poll_session(&invite.session_id)
        .expect("confirmation lost");
    assert!(pending.active_call.is_none());
    assert!(pending.pending_call.expect("still pending").answer_pending);
    net.drop_frames(ALICE_ID, BOB_ID, |_, _| false);
    bob.call_accept(&invite.session_id, &call.call_id)
        .expect("request same answer again");
    alice.poll_session(&invite.session_id).expect("reconfirm");
    assert!(bob
        .poll_session(&invite.session_id)
        .expect("fresh confirmation")
        .active_call
        .is_some());
}

#[test]
fn an_end_delivered_before_its_offer_never_rings_or_replaces_a_new_call() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    let call = alice.call_start(&invite.session_id).expect("start");
    let delayed = net.endpoint(BOB_ID).drain();
    alice
        .call_end(&invite.session_id, &call.call_id, "cancel")
        .expect("cancel before offer arrives");
    assert!(bob
        .poll_session(&invite.session_id)
        .expect("end first")
        .pending_call
        .is_none());
    let replacement = bob
        .call_start(&invite.session_id)
        .expect("new outgoing call");
    for frame in delayed {
        net.endpoint(ALICE_ID)
            .publish(&invite.mesh_id, &frame.channel, &frame.payload)
            .expect("late offer");
    }
    let view = bob
        .poll_session(&invite.session_id)
        .expect("late offer ignored");
    assert!(view.pending_call.is_none(), "ended call must not ring");
    assert!(
        view.active_call.is_none(),
        "ended call must not be auto-answered"
    );
    assert_eq!(
        view.outgoing_call.expect("new call retained").call_id,
        replacement.call_id
    );
}
