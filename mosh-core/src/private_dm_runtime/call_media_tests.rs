//! Voice frames travel through the call media hub, never through the DM
//! runtime: the 20 ms audio loop must not wait on the runtime's lock or its
//! tick. The runtime only tells the hub which calls are live.

use std::sync::Mutex;

use super::state_tests::{accept, connect, invite, memory_pair, ALICE_ID, BOB_ID};
use super::*;

const CALLER_BIT: u64 = 0;
const CALLEE_BIT: u64 = 1 << 63;

fn frame(direction: u64, seq: u64, payload: &[u8]) -> Vec<u8> {
    let mut bytes = (direction | seq).to_be_bytes().to_vec();
    bytes.extend_from_slice(payload);
    bytes
}

/// Alice calls, Bob answers, both see the call active. Returns the ids.
fn active_call(alice: &mut PrivateDmRuntime, bob: &mut PrivateDmRuntime) -> (String, String) {
    let invite = invite(alice);
    accept(bob, &invite);
    connect(alice, bob, &invite.session_id);
    let call = alice
        .call_start(&invite.session_id)
        .expect("Alice should start a call");
    bob.poll_session(&invite.session_id)
        .expect("poll should pass");
    bob.call_accept(&invite.session_id, &call.call_id)
        .expect("Bob should accept");
    let view = alice
        .poll_session(&invite.session_id)
        .expect("poll should pass");
    assert!(view.active_call.is_some(), "Alice saw the accept");
    (invite.session_id, call.call_id)
}

#[test]
fn frames_cross_both_ways_through_the_hub() {
    let (_net, mut alice, mut bob) = memory_pair();
    let (_session_id, call_id) = active_call(&mut alice, &mut bob);
    let (alice_media, bob_media) = (alice.call_media(), bob.call_media());

    let hello = frame(CALLER_BIT, 0, &[1, 2, 3]);
    alice_media.send(&call_id, &hello).expect("send");
    assert_eq!(bob_media.drain(&call_id), vec![hello]);

    let reply = frame(CALLEE_BIT, 0, &[4, 5, 6]);
    bob_media.send(&call_id, &reply).expect("send");
    assert_eq!(alice_media.drain(&call_id), vec![reply]);
}

#[test]
fn our_own_frames_coming_back_are_dropped() {
    let (net, mut alice, mut bob) = memory_pair();
    let (_session_id, call_id) = active_call(&mut alice, &mut bob);
    // Moss delivers a node's own publish back to it; here Bob's endpoint
    // plays that echo with a caller-direction frame.
    net.endpoint(BOB_ID)
        .publish(
            "room",
            &voice_call_channel(&call_id),
            &frame(CALLER_BIT, 7, &[9]),
        )
        .expect("publish");
    assert!(alice.call_media().drain(&call_id).is_empty());
}

#[test]
fn an_ended_call_carries_no_more_frames() {
    let (_net, mut alice, mut bob) = memory_pair();
    let (session_id, call_id) = active_call(&mut alice, &mut bob);
    alice
        .call_end(&session_id, &call_id, "hangup")
        .expect("Alice should hang up");

    bob.call_media()
        .send(&call_id, &frame(CALLEE_BIT, 1, &[1]))
        .expect("a late frame is not an error");
    assert!(alice.call_media().drain(&call_id).is_empty());
}

#[test]
fn media_flows_while_the_runtime_is_locked() {
    let (_net, mut alice, mut bob) = memory_pair();
    let (_session_id, call_id) = active_call(&mut alice, &mut bob);
    let (alice_media, bob_media) = (alice.call_media(), bob.call_media());
    let alice = Mutex::new(alice);

    // A long drain or a stalled chunk would hold this lock in production.
    let _held = alice.lock().expect("lock");
    let voice = frame(CALLER_BIT, 3, &[3]);
    let sent = voice.clone();
    let received = std::thread::spawn(move || {
        alice_media.send(&call_id, &sent).expect("send");
        bob_media.drain(&call_id)
    })
    .join()
    .expect("the media thread never waits on the runtime");
    assert_eq!(received, vec![voice]);
}

// Nobody may drain a live call (its audio loop never started), yet the
// transport's media queue must not grow: the runtime tick files arrivals into
// the hub, which keeps at most one second per call and drops the rest.
#[test]
fn the_tick_empties_the_media_queue_even_with_no_audio_loop() {
    let (net, mut alice, mut bob) = memory_pair();
    let (_session_id, call_id) = active_call(&mut alice, &mut bob);
    let bob_media = bob.call_media();
    for seq in 0..60 {
        bob_media
            .send(&call_id, &frame(CALLEE_BIT, seq, &[1]))
            .expect("send");
    }
    net.endpoint(BOB_ID)
        .publish(
            "room",
            &voice_call_channel("ended-call"),
            &frame(CALLEE_BIT, 0, &[2]),
        )
        .expect("publish");

    alice.service();
    assert!(
        net.endpoint(ALICE_ID).drain_media().is_empty(),
        "the tick took everything off the transport queue"
    );
    assert_eq!(alice.call_media().drain(&call_id).len(), 50);
}
