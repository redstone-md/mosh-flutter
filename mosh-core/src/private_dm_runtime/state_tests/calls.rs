use super::*;

// A hint landing in the ring under the pinned typing code, via the same
// push_app_event insert the node's own reports use.

#[test]
fn a_call_start_failure_frees_the_call_slot() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);

    net.refuse_subscribes(ALICE_ID, true);
    let error = alice
        .call_start(&invite.session_id)
        .expect_err("a subscribe that fails must fail the start");
    assert!(
        matches!(error, PrivateDmRuntimeError::Moss(_)),
        "the subscribe failure surfaces, got {error:?}"
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
    net.refuse_subscribes(ALICE_ID, false);
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

// call_start's publish failure, same contract: the offer that never left must
// clear the slot. The knob here is the hard transport fault — the memory net's
// `refuse_publishes` answers NoPeers, which the control route deliberately
// tolerates.
#[test]
fn a_call_offer_failure_frees_the_call_slot() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);

    net.fail_publishes(ALICE_ID, true);
    alice
        .call_start(&invite.session_id)
        .expect_err("an offer that never left must fail the start");
    {
        let session = alice
            .sessions
            .get_mut(&invite.session_id)
            .expect("Alice session should exist");
        assert!(
            session.call.is_none(),
            "the failed offer leaves no dead call behind"
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

// handle_call_offer: a subscribe failure must roll the stored ring back, or
// the ring ignores every repeated offer (a no-op while a call is held) and
// media can never arrive without the channel subscription.
#[test]
fn a_ring_whose_subscribe_failed_is_retried_by_the_next_offer() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);

    // A real offer for a call Bob knows nothing about yet, minted by the
    // caller's own session so the ciphertext decrypts on Bob's side (MLS
    // cannot decrypt own messages, so Bob could not mint it for himself).
    // One ciphertext per delivery: MLS deletes the secret behind an
    // application message once consumed, which is exactly why the real
    // retransmit path re-encrypts the body on every resend.
    let call_id = "ring-retry-call".to_string();
    let body = || CallOfferBody {
        key_b64: "a2V5".to_string(),
        nonce_prefix_b64: "bm9uY2U".to_string(),
    };
    let mut mint_offer = || {
        let ciphertext = {
            let session = alice
                .sessions
                .get_mut(&invite.session_id)
                .expect("Alice session should exist");
            session
                .crypto
                .encrypt(&serde_json::to_vec(&body()).expect("body should serialize"))
                .expect("Alice-side group can encrypt")
        };
        serde_json::to_vec(&ControlEnvelope::CallOffer {
            session_id: invite.session_id.clone(),
            participant_id: "peer-participant".to_string(),
            from_device: "Alice".to_string(),
            call_id: call_id.clone(),
            offer_ciphertext_b64: encode(&ciphertext),
        })
        .expect("offer should serialize")
    };
    let control = control_channel(&invite.session_id);

    // Bob's subscribe fails: the ring must not be stored against a channel
    // nothing is listening on.
    net.refuse_subscribes(BOB_ID, true);
    {
        let session = bob
            .sessions
            .get_mut(&invite.session_id)
            .expect("Bob session should exist");
        assert!(
            session
                .handle_moss_message(MossReceivedMessage {
                    channel: control.clone(),
                    payload: mint_offer(),
                })
                .is_err(),
            "the subscribe failure surfaces"
        );
        assert!(
            session.call.is_none(),
            "a ring whose subscribe failed is not stored"
        );
    }

    // The caller re-offers the SAME call once the transport heals: the ring
    // now lands and holds — the repair path a pre-stored ring could never
    // take (any other offer while a call is held is a no-op).
    net.refuse_subscribes(BOB_ID, false);
    {
        let session = bob
            .sessions
            .get_mut(&invite.session_id)
            .expect("Bob session should exist");
        session
            .handle_moss_message(MossReceivedMessage {
                channel: control,
                payload: mint_offer(),
            })
            .expect("the healed transport accepts the re-offer");
        assert_eq!(
            session.call.as_ref().expect("ring held").call_id,
            call_id,
            "the re-offer on the healed transport lands as a ring"
        );
    }
}
