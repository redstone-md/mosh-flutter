//! Voice-call state hygiene. Each failure test pins one path in the call
//! state machine: a setup step that fails must leave the session able to try
//! again, never a dead call that only a timeout can clear.
use super::*;
use std::sync::Mutex;

// call_start: an offer that never left must clear the slot, or the dead call
// blocks new calls until the ring budget times out. The knob is the hard
// transport fault: the memory net's `refuse_publishes` answers NoPeers, which
// the control route deliberately tolerates.
#[test]
fn a_call_start_failure_frees_the_call_slot() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);

    net.fail_publishes(ALICE_ID, true);
    let error = alice
        .call_start(&invite.session_id)
        .expect_err("an offer that cannot be published must fail the start");
    assert!(
        matches!(error, PrivateDmRuntimeError::Moss(_)),
        "the publish failure surfaces, got {error:?}"
    );
    {
        let session = alice
            .sessions
            .get_mut(&invite.session_id)
            .expect("Alice session should exist");
        assert!(
            session.call.is_none(),
            "a call whose setup failed must not occupy the slot"
        );
    }

    // The slot is free: a retry once the transport heals starts cleanly.
    net.fail_publishes(ALICE_ID, false);
    let call = alice
        .call_start(&invite.session_id)
        .expect("the healed transport accepts a retry");
    {
        let session = alice
            .sessions
            .get_mut(&invite.session_id)
            .expect("Alice session should exist");
        assert_eq!(
            session.call.as_ref().expect("call held").call_id,
            call.call_id
        );
    }
}

// call_accept: the accept that never left must leave the call ringing, so
// the caller's re-offer re-triggers the accept instead of hitting a local
// state machine that considers itself answered.
#[test]
fn a_failed_accept_goes_back_to_ringing_for_the_retry() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);

    let call = alice
        .call_start(&invite.session_id)
        .expect("Alice should start a call");
    bob.drain_inbound();
    {
        let session = bob
            .sessions
            .get_mut(&invite.session_id)
            .expect("Bob session should exist");
        assert!(
            session
                .call
                .as_ref()
                .is_some_and(|call| call.phase == CallPhase::Ringing),
            "Bob should hold a ringing call"
        );
    }

    net.fail_publishes(BOB_ID, true);
    let call_id = call.call_id.clone();
    bob.call_accept(&invite.session_id, &call_id)
        .expect_err("a publish failure must fail the accept");
    {
        let session = bob
            .sessions
            .get_mut(&invite.session_id)
            .expect("Bob session should exist");
        assert_eq!(
            session.call.as_ref().expect("call held").phase,
            CallPhase::Ringing,
            "the failed accept leaves the call ringing, not active"
        );
    }

    // The retry on the healed transport completes, and the caller sees it.
    net.fail_publishes(BOB_ID, false);
    bob.call_accept(&invite.session_id, &call_id)
        .expect("the healed transport accepts the retry");
    alice.drain_inbound();
    {
        let session = alice
            .sessions
            .get_mut(&invite.session_id)
            .expect("Alice session should exist");
        assert_eq!(
            session.call.as_ref().expect("call held").phase,
            CallPhase::Active,
            "the retried accept reaches the caller"
        );
    }
}

// call_decline: the decline that never left must keep the call held, so the
// user can decline again instead of leaving the peer ringing against a call
// nobody holds.
#[test]
fn a_failed_decline_keeps_the_call_for_a_retry() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);

    let call = alice
        .call_start(&invite.session_id)
        .expect("Alice should start a call");
    bob.drain_inbound();

    net.fail_publishes(BOB_ID, true);
    let call_id = call.call_id.clone();
    bob.call_decline(&invite.session_id, &call_id, "busy")
        .expect_err("a decline that never left must fail");
    {
        let session = bob
            .sessions
            .get_mut(&invite.session_id)
            .expect("Bob session should exist");
        assert!(
            session.call.is_some(),
            "the failed decline keeps the call held for a retry"
        );
        assert!(
            session.messages.iter().all(|message| message
                .call_event
                .as_ref()
                .is_none_or(|event| event.call_id != call_id)),
            "no missed-call history row is logged while the call is still held"
        );
    }

    // The retry on the healed transport declines for real, and the caller
    // sees its call drop.
    net.fail_publishes(BOB_ID, false);
    bob.call_decline(&invite.session_id, &call_id, "busy")
        .expect("the healed transport carries the decline");
    {
        let session = bob
            .sessions
            .get_mut(&invite.session_id)
            .expect("Bob session should exist");
        assert!(
            session.call.is_none(),
            "the successful decline clears the call"
        );
    }
    alice.drain_inbound();
    {
        let session = alice
            .sessions
            .get_mut(&invite.session_id)
            .expect("Alice session should exist");
        assert!(
            session.call.is_none(),
            "the decline reaches the caller and drops its call"
        );
    }
}

// MOSH-89: Moss hands a device its own publishes back. A call control names
// no sender in the clear, so its echo has to be recognised before MLS refuses
// to decrypt it, while the counterpart still reads the very same frame.
#[test]
fn an_echoed_call_control_is_skipped_and_the_counterpart_still_rings() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    let published = Arc::new(Mutex::new(Vec::new()));
    let tap = Arc::clone(&published);
    net.drop_frames(ALICE_ID, BOB_ID, move |_, payload| {
        if payload_says(payload, "CallControl") {
            tap.lock().unwrap().push(payload.to_vec());
        }
        false
    });

    alice
        .call_start(&invite.session_id)
        .expect("Alice should start a call");
    let offer = published.lock().unwrap().pop().expect("the offer left");
    alice
        .sessions
        .get_mut(&invite.session_id)
        .expect("Alice session should exist")
        .handle_moss_message(MossReceivedMessage {
            channel: control_channel(&invite.session_id),
            payload: offer,
        })
        .expect("Alice's own offer coming back is not an inbound failure");

    bob.drain_inbound();
    let session = bob
        .sessions
        .get(&invite.session_id)
        .expect("Bob session should exist");
    assert!(
        session
            .call
            .as_ref()
            .is_some_and(|call| call.phase == CallPhase::Ringing),
        "Bob still rings on the same frame"
    );
}

// The callee declines with "no_answer" once its own ring budget is spent. The
// caller must still be ringing when that decline is due, so the callee's real
// reason reaches it instead of the caller timing out first.
#[test]
fn the_caller_outlasts_the_callee_no_answer_window() {
    const DECLINE_DELIVERY_MS: u64 = 5_000;
    let callee = CallPhase::Ringing.ring_budget_ms().unwrap();
    let (_net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    alice.call_start(&invite.session_id).expect("call starts");
    let session = alice
        .sessions
        .get_mut(&invite.session_id)
        .expect("Alice session should exist");
    let rang = session.call.as_ref().expect("call held").offer_first_ms;

    session.pump_call_signaling(rang + callee + DECLINE_DELIVERY_MS);
    assert!(session.call.is_some(), "the caller still rings");
}

// An answer late in the ring still has to wait for the caller's selection.
// That wait gets its own budget from the moment of the answer, instead of
// inheriting whatever was left of the ring and ending as unanswered.
#[test]
fn a_late_answer_is_not_ended_as_unanswered() {
    let (_net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    let call = alice.call_start(&invite.session_id).expect("call starts");
    bob.drain_inbound();
    let budget = CallPhase::Ringing.ring_budget_ms().unwrap();
    {
        let session = bob
            .sessions
            .get_mut(&invite.session_id)
            .expect("Bob session should exist");
        let ringing = session.call.as_mut().expect("Bob rings");
        ringing.offer_first_ms -= budget - 1_000;
    }

    bob.call_accept(&invite.session_id, &call.call_id)
        .expect("Bob answers a second before the ring ends");
    let session = bob
        .sessions
        .get_mut(&invite.session_id)
        .expect("Bob session should exist");
    session.pump_call_signaling(now_ms() + 2_000);
    assert_eq!(
        session.call.as_ref().map(|call| call.phase),
        Some(CallPhase::Accepting),
        "the answered call waits for the caller's selection"
    );
}
