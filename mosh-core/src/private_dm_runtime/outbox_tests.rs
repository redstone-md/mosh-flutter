//! The DM outbox on the in-memory transport: a text is queued before the
//! transport is asked anything, leaves oldest first once the counterpart is
//! reachable, and never fails on a refusal. Helpers come from
//! `state_tests.rs`.

use super::state_tests::{accept, connect, invite, memory_pair, runtime_on, ALICE_ID, BOB_ID};
use super::tests::temp_store;
use super::*;
use crate::persistence::Persistence;
use crate::private_dm_runtime::transport::memory::MemoryNet;

fn status_of(
    runtime: &mut PrivateDmRuntime,
    session_id: &str,
    message_id: &str,
) -> Option<MessageDeliveryStatus> {
    runtime
        .poll_session(session_id)
        .expect("poll should pass")
        .messages
        .iter()
        .find(|message| message.message_id.as_deref() == Some(message_id))
        .and_then(|message| message.delivery_status)
}

fn bodies_from(runtime: &mut PrivateDmRuntime, session_id: &str, author: &str) -> Vec<String> {
    runtime
        .poll_session(session_id)
        .expect("poll should pass")
        .messages
        .iter()
        .filter(|message| message.from_device == author)
        .map(|message| message.body.clone())
        .collect()
}

#[test]
fn queued_messages_come_out_oldest_first() {
    let attempt =
        |id: &str, sent_at_ms: u64, status: MessageDeliveryStatus| OutboundAttemptRecord {
            conversation_id: "s".to_string(),
            message_id: id.to_string(),
            sent_at_ms,
            ciphertext_bytes: 0,
            message_json: String::new(),
            publish_payload_b64: String::new(),
            delivery_status: status,
            delivery_error: None,
            retry_count: 0,
            auto_resends: 0,
            last_send_ms: 0,
        };
    let attempts: HashMap<String, OutboundAttemptRecord> = [
        ("late", 30, MessageDeliveryStatus::Queued),
        ("early", 10, MessageDeliveryStatus::Queued),
        ("sent", 5, MessageDeliveryStatus::Sent),
        ("middle", 20, MessageDeliveryStatus::Queued),
        ("failed", 1, MessageDeliveryStatus::Failed),
    ]
    .into_iter()
    .map(|(id, at, status)| (id.to_string(), attempt(id, at, status)))
    .collect();

    assert_eq!(queued_in_order(&attempts), vec!["early", "middle", "late"]);
}

// Three texts typed before anybody joined wait as Queued, leave in the order
// they were written once the pair is connected, and go Sent then Delivered.
#[test]
fn texts_queued_before_the_handshake_arrive_in_order() {
    let (_net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    let ids: Vec<String> = ["one", "two", "three"]
        .into_iter()
        .map(|body| {
            let sent = alice
                .send_message(&invite.session_id, body.to_string())
                .expect("a text never fails to queue");
            assert_eq!(sent.delivery_status, MessageDeliveryStatus::Queued);
            assert_eq!(sent.delivery_error, None);
            sent.message_id
        })
        .collect();

    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);

    assert_eq!(
        bodies_from(&mut bob, &invite.session_id, "Alice"),
        vec!["one", "two", "three"]
    );
    // Bob acked on receipt; Alice's next drain settles every one Delivered.
    for id in &ids {
        assert_eq!(
            status_of(&mut alice, &invite.session_id, id),
            Some(MessageDeliveryStatus::Delivered)
        );
    }
}

// The invitee has no MLS group until the Welcome lands, and still gets to
// type: the text waits as Queued and goes out once he has joined.
#[test]
fn the_invitee_queues_texts_before_the_welcome() {
    let (net, mut alice, mut bob) = memory_pair();
    // Nothing reaches Alice until the invitee's text is queued.
    net.link(BOB_ID, ALICE_ID, PeerTransport::None);
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    let sent = bob
        .send_message(&invite.session_id, "typed before the welcome".to_string())
        .expect("a text never fails to queue");
    assert_eq!(sent.delivery_status, MessageDeliveryStatus::Queued);
    assert_eq!(
        status_of(&mut bob, &invite.session_id, &sent.message_id),
        Some(MessageDeliveryStatus::Queued),
        "no group yet, so the text waits"
    );

    net.link(BOB_ID, ALICE_ID, PeerTransport::Direct);
    // The first KeyPackage went nowhere; the handshake pump repeats it on
    // its cadence, crossed here by the clock rather than by waiting.
    bob.tick(now_ms() + HANDSHAKE_RESEND_MS);
    connect(&mut alice, &mut bob, &invite.session_id);
    assert_eq!(
        bodies_from(&mut alice, &invite.session_id, "Bob"),
        vec!["typed before the welcome"]
    );
}

// A transport refusal is not the user's problem: the text stays Queued with
// no error and goes out by itself when the transport takes frames again.
#[test]
fn a_refused_publish_leaves_the_text_queued_not_failed() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);

    net.refuse_publishes(ALICE_ID, true);
    let sent = alice
        .send_message(&invite.session_id, "later".to_string())
        .expect("a refusal is not an error");
    assert_eq!(sent.delivery_status, MessageDeliveryStatus::Queued);
    assert_eq!(sent.delivery_error, None);
    let view = alice
        .poll_session(&invite.session_id)
        .expect("poll should pass");
    let message = view
        .messages
        .iter()
        .find(|message| message.message_id.as_deref() == Some(sent.message_id.as_str()))
        .expect("the message is in the log");
    assert_eq!(message.delivery_status, Some(MessageDeliveryStatus::Queued));
    assert_eq!(message.retryable, Some(false), "nothing to retry by hand");

    net.refuse_publishes(ALICE_ID, false);
    assert_eq!(
        status_of(&mut alice, &invite.session_id, &sent.message_id),
        Some(MessageDeliveryStatus::Sent)
    );
    assert_eq!(
        bodies_from(&mut bob, &invite.session_id, "Alice"),
        vec!["later"]
    );
    assert_eq!(
        status_of(&mut alice, &invite.session_id, &sent.message_id),
        Some(MessageDeliveryStatus::Delivered)
    );
}

// Closing the laptop must not lose what was typed: a queued text is on disk
// as Queued, comes back Queued, and leaves once the pair connects.
#[test]
fn queued_texts_survive_a_restart_and_go_out_on_connect() {
    let mut db_path = std::env::temp_dir();
    db_path.push(format!(
        "mosh-dm-queued-restart-{}.redb",
        std::process::id()
    ));
    let _ = std::fs::remove_file(&db_path);
    let persistence =
        Arc::new(Persistence::open_with_dek(&db_path, [11u8; 32]).expect("store should open"));
    let net = MemoryNet::new();

    let (invite, message_id) = {
        let mut alice = PrivateDmRuntime::with_transport(
            net.endpoint(ALICE_ID),
            temp_store(),
            Some(Arc::clone(&persistence)),
        );
        let invite = invite(&mut alice);
        let sent = alice
            .send_message(&invite.session_id, "typed before the restart".to_string())
            .expect("send should queue");
        assert_eq!(sent.delivery_status, MessageDeliveryStatus::Queued);
        (invite, sent.message_id)
    };

    let mut revived =
        PrivateDmRuntime::with_transport(net.endpoint(ALICE_ID), temp_store(), Some(persistence));
    revived.rehydrate();
    assert_eq!(
        status_of(&mut revived, &invite.session_id, &message_id),
        Some(MessageDeliveryStatus::Queued)
    );

    net.link_both(ALICE_ID, BOB_ID, PeerTransport::Direct);
    let mut bob = runtime_on(&net, BOB_ID);
    accept(&mut bob, &invite);
    connect(&mut revived, &mut bob, &invite.session_id);
    assert_eq!(
        bodies_from(&mut bob, &invite.session_id, "Alice"),
        vec!["typed before the restart"]
    );
    let _ = std::fs::remove_file(&db_path);
}

// A text that an older build left Failed is re-queued by Retry; a Retry on
// a text that is already waiting changes nothing and reports it as it is.
#[test]
fn retry_requeues_a_failed_text() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);

    net.link(ALICE_ID, BOB_ID, PeerTransport::None);
    let sent = alice
        .send_message(&invite.session_id, "retry me".to_string())
        .expect("send should queue");
    let again = alice
        .retry_message(&invite.session_id, &sent.message_id)
        .expect("a queued text has nothing to retry and nothing to complain about");
    assert_eq!(again.delivery_status, MessageDeliveryStatus::Queued);
    // The shape an older build leaves behind.
    alice
        .sessions
        .get_mut(&invite.session_id)
        .expect("Alice session")
        .outbox()
        .settle(
            &sent.message_id,
            Err("older build".to_string()),
            OnSent::Retain,
        )
        .expect("settle");
    assert_eq!(
        status_of(&mut alice, &invite.session_id, &sent.message_id),
        Some(MessageDeliveryStatus::Failed)
    );

    let retried = alice
        .retry_message(&invite.session_id, &sent.message_id)
        .expect("retry should requeue");
    assert_eq!(retried.message_id, sent.message_id);
    assert_eq!(retried.delivery_status, MessageDeliveryStatus::Queued);

    net.link(ALICE_ID, BOB_ID, PeerTransport::Direct);
    assert_eq!(
        status_of(&mut alice, &invite.session_id, &sent.message_id),
        Some(MessageDeliveryStatus::Sent)
    );
}

// Unacked Sent messages re-publish on the resend cadence and give up
// (keeping Sent) after AUTO_RESEND_MAX tries; a refused re-send burns no slot.
#[test]
fn unacked_sent_message_auto_resends_then_gives_up() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    let sent = alice
        .send_message(&invite.session_id, "ping".to_string())
        .expect("send should go out");
    assert_eq!(sent.delivery_status, MessageDeliveryStatus::Sent);
    let message_id = sent.message_id;

    let session = alice
        .sessions
        .get_mut(&invite.session_id)
        .expect("Alice session should exist");
    // Not due yet: last_send_ms is fresh.
    assert!(session.pump_unacked_resends(now_ms()).is_empty());

    session
        .outbound_attempts
        .get_mut(&message_id)
        .expect("attempt retained")
        .last_send_ms = 0;
    net.refuse_publishes(ALICE_ID, true);
    assert!(
        session.pump_unacked_resends(now_ms()).is_empty(),
        "a refused publish is not a resend"
    );
    net.refuse_publishes(ALICE_ID, false);
    assert_eq!(session.outbound_attempts[&message_id].auto_resends, 0);

    for expected in 1..=AUTO_RESEND_MAX {
        session
            .outbound_attempts
            .get_mut(&message_id)
            .expect("attempt retained")
            .last_send_ms = 0;
        let changed = session.pump_unacked_resends(now_ms());
        assert_eq!(changed, vec![message_id.clone()], "resend #{expected}");
        assert_eq!(
            session.outbound_attempts[&message_id].auto_resends,
            expected
        );
    }
    // Cap reached: the loop stops but the attempt SURVIVES, so the ack can
    // still land later.
    session
        .outbound_attempts
        .get_mut(&message_id)
        .expect("attempt survives the cap")
        .last_send_ms = 0;
    assert!(session.pump_unacked_resends(now_ms()).is_empty());
    let message = session
        .messages
        .iter()
        .find(|m| m.message_id.as_deref() == Some(message_id.as_str()))
        .expect("message exists");
    assert_eq!(message.delivery_status, Some(MessageDeliveryStatus::Sent));
}
