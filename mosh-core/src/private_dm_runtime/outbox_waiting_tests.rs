//! A queued text for a counterpart nobody can reach waits for it instead of
//! being encrypted, published and logged on every tick, and leaves once the
//! counterpart shows up again.

use super::state_tests::{
    accept, bodies_from, connect, invite, log_lines, memory_pair, status_of, ALICE_ID, BOB_ID,
};
use super::*;
use crate::private_dm_runtime::transport::memory::MemoryNet;

const TICKS: u64 = 20;
const TICK_MS: u64 = 500;

/// A text Alice queued while Bob was gone, after the service ticked on.
struct Waiting {
    message_id: String,
    now: u64,
}

fn queued_while_away(net: &MemoryNet, alice: &mut PrivateDmRuntime, session_id: &str) -> Waiting {
    net.link_both(ALICE_ID, BOB_ID, PeerTransport::None);
    let start = now_ms();
    alice.drain_inbound_at(start);
    let sent = alice
        .send_message(session_id, "while you were away".to_string())
        .expect("a refusal is not an error");
    assert_eq!(sent.delivery_status, MessageDeliveryStatus::Queued);
    for i in 1..=TICKS {
        alice.drain_inbound_at(start + i * TICK_MS);
    }
    Waiting {
        message_id: sent.message_id,
        now: start + TICKS * TICK_MS,
    }
}

#[test]
fn a_text_for_an_unreachable_peer_is_tried_once_then_waits() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    let data = ChannelKind::Data.channel_for(&invite.session_id);
    let before = net.publish_attempts(ALICE_ID, &data);

    let waiting = queued_while_away(&net, &mut alice, &invite.session_id);

    assert_eq!(net.publish_attempts(ALICE_ID, &data) - before, 1);
    assert_eq!(log_lines(&waiting.message_id, "stays queued").len(), 1);

    net.link_both(ALICE_ID, BOB_ID, PeerTransport::Direct);
    alice.drain_inbound_at(waiting.now + TICK_MS);
    assert_eq!(
        status_of(&mut alice, &invite.session_id, &waiting.message_id),
        Some(MessageDeliveryStatus::Sent),
        "a path to Bob ends the wait"
    );
    assert_eq!(
        bodies_from(&mut bob, &invite.session_id, "Alice"),
        vec!["while you were away"]
    );
}

// Gossip can carry a chat while moss lists no row for the counterpart, so a
// frame from it ends the wait as surely as a path does.
#[test]
fn a_frame_from_an_unlisted_peer_ends_the_wait() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    let waiting = queued_while_away(&net, &mut alice, &invite.session_id);

    net.link_both(ALICE_ID, BOB_ID, PeerTransport::Direct);
    net.unlist(ALICE_ID, BOB_ID);
    alice.drain_inbound_at(waiting.now + TICK_MS);
    assert_eq!(
        status_of(&mut alice, &invite.session_id, &waiting.message_id),
        Some(MessageDeliveryStatus::Queued),
        "no path is listed and nothing came from Bob yet"
    );

    bob.send_message(&invite.session_id, "back".to_string())
        .expect("Bob should send");
    alice.drain_inbound_at(waiting.now + 2 * TICK_MS);
    alice.drain_inbound_at(waiting.now + 3 * TICK_MS);
    assert_eq!(
        bodies_from(&mut bob, &invite.session_id, "Alice"),
        vec!["while you were away"]
    );
}

// Moss can refuse while it lists the counterpart. The outbox then keeps
// trying on every tick, and says so once.
#[test]
fn a_refusal_with_a_known_path_is_retried_but_logged_once() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    let data = ChannelKind::Data.channel_for(&invite.session_id);
    net.refuse_publishes(ALICE_ID, true);
    let before = net.publish_attempts(ALICE_ID, &data);

    let sent = alice
        .send_message(&invite.session_id, "refused".to_string())
        .expect("a refusal is not an error");
    let start = now_ms();
    for i in 1..=3 {
        alice.drain_inbound_at(start + i * TICK_MS);
    }

    assert_eq!(net.publish_attempts(ALICE_ID, &data) - before, 4);
    assert_eq!(log_lines(&sent.message_id, "stays queued").len(), 1);
}
