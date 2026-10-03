use super::*;

// The full loop: Alice's keystrokes fold to one frame on the wire, Bob's
// poll raises the hint from his own clock, and a real message stops it.
#[test]
fn typing_signal_travels_and_a_message_stops_it() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);

    // One keystroke: exactly one frame on the wire, body encrypted.
    alice
        .typing_signal(&invite.session_id)
        .expect("Alice signal should pass");
    // Draining Bob's inbox IS the delivery — keep a copy to hand back below.
    let wire = net.endpoint(BOB_ID).drain();
    let hint_frame = wire
        .iter()
        .find(|frame| payload_says(&frame.payload, "TypingIndicator"))
        .expect("one typing frame should be on the wire");
    assert!(
        !payload_says(&hint_frame.payload, "until_ms"),
        "the hint body travels encrypted, never in the clear"
    );
    // Hand the observed frames back to Bob the same way MemoryNet delivers
    // anything: over Alice's outbound link (a publish routes along the
    // publisher's own links).
    for frame in &wire {
        net.endpoint(ALICE_ID)
            .publish(&invite.mesh_id, &frame.channel, &frame.payload)
            .expect("replay of an observed frame is a publish");
    }

    // Bob drains: the hint stands, stamped from HIS clock (Alice's
    // advisory `until_ms` is not trusted). The receiver's window is the
    // expiry constant wide: the stamp is delivery time plus the constant,
    // within a decrypt's worth of wall-clock skew either way.
    let delivery_wall = now_ms();
    let hint = bob_hint(&mut bob, &invite.session_id).expect("Bob should see typing");
    let window = hint.saturating_sub(delivery_wall);
    assert!(
        window.abs_diff(TYPING_EXPIRY_MS) < 100,
        "the receiver's window is the expiry constant wide, got {window}ms"
    );

    // Continued input inside the refresh window: no second frame goes out.
    alice
        .typing_signal(&invite.session_id)
        .expect("second signal should pass");
    assert_eq!(
        typing_frames(&net, BOB_ID),
        0,
        "a keystroke inside the cadence emits nothing"
    );

    // A real message contradicts "typing": Bob's hint dies at once.
    alice
        .send_message(&invite.session_id, "typing is over".to_string())
        .expect("Alice should send");
    alice.drain_inbound();
    bob.drain_inbound();
    bob.poll_session(&invite.session_id)
        .expect("Bob poll should pass");
    assert!(
        bob_hint(&mut bob, &invite.session_id).is_none(),
        "an inbound message clears the hint"
    );
}

// The sender-side refresh throttle folds rapid keystrokes into one frame per
// cadence, and the next keystroke past the cadence emits again. Observed on
// the wire, not the clock.
#[test]
fn typing_refresh_folds_keystrokes_to_one_frame_per_cadence() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);

    for _ in 0..5 {
        alice
            .typing_signal(&invite.session_id)
            .expect("rapid keystrokes should pass");
    }
    assert_eq!(typing_frames(&net, BOB_ID), 1, "five keystrokes, one frame");

    // Cross the cadence the way a real clock would: the throttle reads the
    // session's last-send stamp, so aging it by the cadence (arithmetic, no
    // sleep) opens the window for the next keystroke.
    {
        let session = alice
            .sessions
            .get_mut(&invite.session_id)
            .expect("Alice session should exist");
        session.typing_gate.age_by(TYPING_REFRESH_MS);
    }
    alice
        .typing_signal(&invite.session_id)
        .expect("third signal should pass");
    assert_eq!(
        typing_frames(&net, BOB_ID),
        1,
        "a refresh after the cadence re-emits"
    );
    let _ = &mut bob;
}

// 5s expiry without sleeps: drive the tick with a fake clock directly. A
// hint inside its window survives; the same hint is gone past the window.
#[test]
fn typing_hint_expires_after_the_window_without_sleeping() {
    let (_net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);

    alice
        .typing_signal(&invite.session_id)
        .expect("Alice signal should pass");
    bob.drain_inbound();
    let deadline = {
        let session = bob
            .sessions
            .get_mut(&invite.session_id)
            .expect("Bob session should exist");
        let deadline = session
            .peer_typing_until_ms
            .expect("the hint stands after the drain");
        // Just inside the window the hint survives the tick...
        session.expire_peer_typing(deadline - 1);
        assert!(
            session.peer_typing_until_ms.is_some(),
            "a hint inside its window stands"
        );
        deadline
    };
    // ...and past it, the tick drops the hint. The expiry is the advertised
    // 5s window: measured from whenever the frame landed, no sleeps.
    assert!(
        deadline.saturating_sub(now_ms()) <= TYPING_EXPIRY_MS,
        "the window is the expiry constant wide"
    );
    let session = bob
        .sessions
        .get_mut(&invite.session_id)
        .expect("Bob session should exist");
    session.expire_peer_typing(deadline);
    assert!(
        session.peer_typing_until_ms.is_none(),
        "a lapsed hint is gone"
    );
}

// A forged plaintext hint (garbage ciphertext) never raises Bob's hint: the
// MLS decrypt is the only door. A replayed ciphertext minted by the group's
// own member is equally dead — MLS cannot decrypt own messages.
#[test]
fn forged_typing_indicator_does_not_set_the_hint() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);

    let forged = serde_json::to_vec(&ControlEnvelope::TypingIndicator {
        session_id: invite.session_id.clone(),
        participant_id: "peer-participant".to_string(),
        from_device: "Alice".to_string(),
        typing_ciphertext_b64: encode(b"not-an-mls-ciphertext"),
    })
    .expect("forged envelope should serialize");
    publish_to_bob(&net, &invite, &forged);
    assert!(
        bob_hint(&mut bob, &invite.session_id).is_none(),
        "a hint that cannot decrypt must not stand"
    );

    // A ciphertext minted by this very group member (MLS cannot decrypt own
    // messages, so even this is rejected) — the DeliveryAck replay pattern.
    let self_minted = {
        let session = alice
            .sessions
            .get_mut(&invite.session_id)
            .expect("Alice session should exist");
        let body = TypingBody {
            device: "Alice".to_string(),
            until_ms: now_ms() + TYPING_EXPIRY_MS,
        };
        let ciphertext = session
            .crypto
            .encrypt(&serde_json::to_vec(&body).expect("body should serialize"))
            .expect("Alice should encrypt");
        serde_json::to_vec(&ControlEnvelope::TypingIndicator {
            session_id: invite.session_id.clone(),
            participant_id: "peer-participant".to_string(),
            from_device: "Alice".to_string(),
            typing_ciphertext_b64: encode(&ciphertext),
        })
        .expect("self-minted envelope should serialize")
    };
    publish_to_bob(&net, &invite, &self_minted);
    assert!(
        bob_hint(&mut bob, &invite.session_id).is_none(),
        "an MLS-unreadable hint is dropped, hint stays down"
    );
}

// Old-client tolerance rides the established unknown-variant decode-drop:
// an envelope whose variant name a build does not know fails decode_json,
// the drain drops it, and the runtime reports no error.
#[test]
fn an_unknown_envelope_variant_is_dropped_by_the_drain() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);

    // What a NEWER client sends that this build does not know.
    let future = serde_json::json!({
        "type": "PresencePing",
        "session_id": invite.session_id,
        "participant_id": "peer-participant",
        "from_device": "Alice",
    });
    let bytes = serde_json::to_vec(&future).expect("future envelope should serialize");

    // Pin the mechanism itself first: the unknown variant name fails decode.
    assert!(
        decode_json::<ControlEnvelope>(&bytes).is_err(),
        "an unknown variant name must fail decode"
    );

    publish_to_bob(&net, &invite, &bytes);
    // The drain must neither error nor raise anything: the decode-drop is
    // the whole recovery, exactly as the mixed-version story promises.
    bob.drain_inbound();
    assert!(bob_hint(&mut bob, &invite.session_id).is_none());
    let _ = alice;
}

#[test]
fn a_landed_hint_files_a_typing_event_into_the_ring() {
    let (_net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);

    crate::moss_ffi::clear_event_log();
    alice
        .typing_signal(&invite.session_id)
        .expect("Alice signal should pass");
    bob.drain_inbound();

    let events = crate::moss_ffi::snapshot_event_log();
    assert!(
        events
            .iter()
            .any(|event| event.event_type == TYPING_EVENT_CODE
                && event.detail_json.contains(&invite.session_id)),
        "the synthesized typing event lands in the ring the panel polls"
    );
}

// ---- voice-call state hygiene ------------------------------------------
//
// Each of these pins one failure path in the call state machine: a setup step
// that fails must leave the session able to try again, never a dead call that
// only a timeout can clear.

// call_start: a subscribe or offer that never left must clear the slot, or
// the dead call blocks new calls until the ring budget times out.
