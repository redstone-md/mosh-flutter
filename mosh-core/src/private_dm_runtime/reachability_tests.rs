//! Connected is a claim about the counterpart, proven by authenticated
//! frames. It is not a claim about moss's peer table: gossip carries a chat
//! through other peers while moss lists no row for the counterpart, and the
//! field saw the state flip every few seconds when the table decided it.
//! Clocks are passed to `tick`, so windows are crossed by arithmetic.

use super::state_tests::{accept, connect, invite, memory_pair, state_of, ALICE_ID, BOB_ID};
use super::*;
use crate::private_dm_runtime::transport::memory::MemoryNet;

/// A connected pair whose moss lists no row for each other, while room
/// frames still cross.
fn unlisted_pair() -> (Arc<MemoryNet>, PrivateDmRuntime, PrivateDmRuntime, String) {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    net.unlist(ALICE_ID, BOB_ID);
    net.unlist(BOB_ID, ALICE_ID);
    (net, alice, bob, invite.session_id)
}

fn hellos_waiting_for(net: &Arc<MemoryNet>, peer_id: &str) -> usize {
    net.endpoint(peer_id)
        .drain()
        .iter()
        .filter(|frame| String::from_utf8_lossy(&frame.payload).contains("Hello"))
        .count()
}

#[test]
fn a_chat_over_gossip_stays_connected_without_a_peer_table_row() {
    let (_net, mut alice, mut bob, session_id) = unlisted_pair();
    let start = now_ms();
    alice.drain_inbound_at(start);
    // Bob keeps talking every 6 s for longer than the lost window; moss never
    // lists him.
    for step in 1..=6 {
        bob.send_message(&session_id, format!("line {step}"))
            .expect("Bob should send");
        alice.drain_inbound_at(start + step * 6_000);
        let view = alice.poll_session(&session_id).expect("poll should pass");
        assert_eq!(view.state, DmSessionState::Connected, "step {step}");
        assert_eq!(
            view.transport,
            PeerTransport::None,
            "the transport label still says moss lists no path"
        );
    }
}

#[test]
fn keepalives_hold_a_quiet_chat_connected() {
    let (_net, mut alice, mut bob, session_id) = unlisted_pair();
    let start = now_ms();
    alice.drain_inbound_at(start);
    // Nobody types. Alice's keepalive goes out, Bob answers on receipt.
    alice.drain_inbound_at(start + KEEPALIVE_MS);
    bob.drain_inbound_at(start + KEEPALIVE_MS);
    alice.drain_inbound_at(start + KEEPALIVE_MS + 100);

    // The answer restarted Alice's window.
    alice.drain_inbound_at(start + KEEPALIVE_MS + LOST_WINDOW_MS - 1_000);
    let view = alice.poll_session(&session_id).expect("poll should pass");
    assert_eq!(view.state, DmSessionState::Connected);
}

#[test]
fn silence_for_the_lost_window_reads_as_offline_until_a_frame() {
    let (net, mut alice, mut bob, session_id) = unlisted_pair();
    net.drop_frames(BOB_ID, ALICE_ID, |_, _| true);
    let start = now_ms();
    alice.drain_inbound_at(start);
    alice.drain_inbound_at(start + LOST_WINDOW_MS);
    assert_eq!(
        alice.poll_session(&session_id).expect("poll").state,
        DmSessionState::Handshaking
    );

    net.drop_frames(BOB_ID, ALICE_ID, |_, _| false);
    bob.send_message(&session_id, "back".to_string())
        .expect("Bob should send");
    assert_eq!(state_of(&mut alice, &session_id), DmSessionState::Connected);
}

#[test]
fn a_keepalive_goes_out_only_after_a_quiet_spell() {
    let (net, mut alice, _bob, _session_id) = unlisted_pair();
    let start = now_ms();
    alice.drain_inbound_at(start);
    hellos_waiting_for(&net, BOB_ID);

    alice.drain_inbound_at(start + 1_000);
    assert_eq!(
        hellos_waiting_for(&net, BOB_ID),
        0,
        "a fresh session is quiet"
    );

    alice.drain_inbound_at(start + KEEPALIVE_MS);
    assert_eq!(hellos_waiting_for(&net, BOB_ID), 1);
}

#[test]
fn a_text_goes_out_over_gossip_without_a_peer_table_row() {
    let (_net, mut alice, mut bob, session_id) = unlisted_pair();
    let sent = alice
        .send_message(&session_id, "over gossip".to_string())
        .expect("a text never fails to queue");
    assert_eq!(sent.delivery_status, MessageDeliveryStatus::Sent);

    let bob_view = bob.poll_session(&session_id).expect("poll should pass");
    assert!(bob_view
        .messages
        .iter()
        .any(|message| message.body == "over gossip"));
}

// The service thread drives the protocol with no UI poll: a handshake
// completes on `service` alone, read back without a poll (a poll drains).
#[test]
fn the_service_tick_alone_completes_a_handshake() {
    let (_net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    let state = |runtime: &PrivateDmRuntime| {
        runtime
            .sessions
            .get(&invite.session_id)
            .map(|session| session.state)
    };
    for _ in 0..10 {
        alice.service();
        bob.service();
    }
    assert_eq!(state(&alice), Some(DmSessionState::Connected));
    assert_eq!(state(&bob), Some(DmSessionState::Connected));
}
