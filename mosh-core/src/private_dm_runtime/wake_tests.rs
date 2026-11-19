//! Waking a counterpart device through its wake service, driven through the
//! runtime's public API on the in-memory transport.

use super::super::state_tests::{accept, connect, invite, memory_pair, state_of, ALICE_ID, BOB_ID};
use super::super::tests::temp_store;
use super::super::wake_preview::MESSAGE_WAKE_GAP_MS;
use super::*;
use crate::private_dm_runtime::transport::memory::MemoryNet;

pub(crate) const SERVICE: &str = "https://wake.example";
pub(crate) const HANDLE: &str = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJ0123456";

fn address(handle: &str) -> WakeAddress {
    WakeAddress {
        service: SERVICE.to_string(),
        handle: handle.to_string(),
    }
}

/// Alice announced a wake address and Bob has it; both are connected.
pub(crate) fn announced_pair() -> (Arc<MemoryNet>, PrivateDmRuntime, PrivateDmRuntime, String) {
    let (net, mut alice, mut bob) = memory_pair();
    alice.set_wake_address(address(HANDLE));
    bob.set_wake_service(SERVICE.to_string());
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    exchange(&mut alice, &mut bob, &invite.session_id);
    (net, alice, bob, invite.session_id)
}

/// A few polls on both sides, enough for one control frame to cross.
pub(crate) fn exchange(alice: &mut PrivateDmRuntime, bob: &mut PrivateDmRuntime, session_id: &str) {
    for _ in 0..3 {
        state_of(alice, session_id);
        state_of(bob, session_id);
    }
}

/// Bob's clock once Alice has been silent for the whole lost window.
pub(crate) fn after_silence() -> u64 {
    now_ms() + LOST_WINDOW_MS
}

fn call_wake(call_id: &str) -> WakeRequest {
    WakeRequest {
        service: SERVICE.to_string(),
        handle: HANDLE.to_string(),
        call_id: Some(call_id.to_string()),
        preview: None,
    }
}

/// The text wakes taken, without their sealed previews (wake_preview_tests).
fn text_wakes(bob: &mut PrivateDmRuntime) -> Vec<WakeRequest> {
    bob.take_wake_requests()
        .into_iter()
        .map(|request| WakeRequest {
            preview: None,
            ..request
        })
        .collect()
}

// The session is no longer Connected once Alice has been silent for the
// lost window; her address is what lets the call ring her at all.
#[test]
fn a_call_wakes_a_device_that_went_away_once() {
    let (net, _alice, mut bob, session_id) = announced_pair();
    net.link_both(ALICE_ID, BOB_ID, PeerTransport::None);
    let later = after_silence();
    bob.drain_inbound_at(later);
    assert_ne!(state_of(&mut bob, &session_id), DmSessionState::Connected);

    let call = bob
        .call_start(&session_id)
        .expect("Bob calls the absent Alice");
    bob.drain_inbound_at(later + CALL_RESEND_MS);
    assert_eq!(bob.take_wake_requests(), vec![call_wake(&call.call_id)]);

    bob.drain_inbound_at(later + 2 * CALL_RESEND_MS);
    assert!(bob.take_wake_requests().is_empty(), "one wake per call");
}

// Locked a moment before the call, the phone must be woken early in the
// ring, not after the whole lost window.
#[test]
fn a_ringing_call_wakes_a_device_soon_after_it_goes_quiet() {
    let (net, _alice, mut bob, session_id) = announced_pair();
    let call = bob.call_start(&session_id).expect("Bob calls");
    net.link_both(ALICE_ID, BOB_ID, PeerTransport::None);
    let start = now_ms();

    bob.drain_inbound_at(start + KEEPALIVE_MS / 2);
    assert!(bob.take_wake_requests().is_empty(), "Alice was just heard");
    bob.drain_inbound_at(start + KEEPALIVE_MS + 2_000);
    assert_eq!(bob.take_wake_requests(), vec![call_wake(&call.call_id)]);
}

#[test]
fn a_call_to_an_absent_counterpart_without_an_address_is_refused() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    net.link_both(ALICE_ID, BOB_ID, PeerTransport::None);
    bob.drain_inbound_at(after_silence());

    assert!(matches!(
        bob.call_start(&invite.session_id),
        Err(PrivateDmRuntimeError::NotReady)
    ));
}

// A contact names its service; only the build's own is asked, or a contact
// could point this device's requests anywhere.
#[test]
fn an_address_on_another_service_wakes_nothing() {
    let (net, _alice, mut bob, session_id) = announced_pair();
    bob.set_wake_service("https://other.example".to_string());
    net.link_both(ALICE_ID, BOB_ID, PeerTransport::None);
    bob.drain_inbound_at(after_silence());

    assert!(matches!(
        bob.call_start(&session_id),
        Err(PrivateDmRuntimeError::NotReady)
    ));
    bob.send_message(&session_id, "hi".to_string())
        .expect("a text for an absent peer queues");
    bob.drain_inbound_at(after_silence() + MESSAGE_WAKE_GAP_MS);
    assert!(bob.take_wake_requests().is_empty());
}

#[test]
fn a_build_without_a_wake_service_wakes_nobody() {
    let (net, mut alice, mut bob) = memory_pair();
    alice.set_wake_address(address(HANDLE));
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    exchange(&mut alice, &mut bob, &invite.session_id);
    net.link_both(ALICE_ID, BOB_ID, PeerTransport::None);
    bob.drain_inbound_at(after_silence());

    assert!(matches!(
        bob.call_start(&invite.session_id),
        Err(PrivateDmRuntimeError::NotReady)
    ));
}

// Like every authenticated control frame, an announcement proves the
// counterpart is still there.
#[test]
fn a_wake_announcement_keeps_the_counterpart_connected() {
    let (_net, mut alice, mut bob, session_id) = announced_pair();
    let ciphertext = alice
        .sessions
        .get_mut(&session_id)
        .expect("Alice's chat")
        .crypto
        .encrypt_json(&announcement(HANDLE, SERVICE, now_ms() + 1))
        .expect("sealed");
    bob.sessions
        .get_mut(&session_id)
        .expect("Bob's chat")
        .accept_wake_address(&ciphertext)
        .expect("accepted");

    bob.drain_inbound_at(after_silence());

    assert_eq!(state_of(&mut bob, &session_id), DmSessionState::Connected);
}

// A device that is still heard is reached over Moss; waking it is waste.
#[test]
fn a_call_to_a_device_still_heard_wakes_nothing() {
    let (_net, _alice, mut bob, session_id) = announced_pair();

    bob.call_start(&session_id).expect("Bob calls");
    bob.drain_inbound_at(now_ms());

    assert!(bob.take_wake_requests().is_empty());
}

#[test]
fn a_withdrawn_address_wakes_nothing() {
    let (net, mut alice, mut bob, session_id) = announced_pair();
    alice.set_wake_address(address(""));
    exchange(&mut alice, &mut bob, &session_id);
    net.link_both(ALICE_ID, BOB_ID, PeerTransport::None);

    bob.call_start(&session_id).expect("Bob calls");
    bob.drain_inbound_at(after_silence());

    assert!(bob.take_wake_requests().is_empty());
}

// A chat wakes a phone for texts once per gap at most, and one wake stands
// for every text queued with it.
#[test]
fn queued_texts_wake_an_absent_device_once_per_batch() {
    let (net, _alice, mut bob, session_id) = announced_pair();
    net.link_both(ALICE_ID, BOB_ID, PeerTransport::None);
    let text_wake = WakeRequest {
        call_id: None,
        ..call_wake("")
    };
    let send = |bob: &mut PrivateDmRuntime, body: &str| {
        bob.send_message(&session_id, body.to_string())
            .expect("a text for an absent peer queues");
    };

    send(&mut bob, "first");
    send(&mut bob, "second");
    let later = after_silence();
    bob.drain_inbound_at(later);
    assert_eq!(text_wakes(&mut bob), vec![text_wake.clone()]);

    bob.drain_inbound_at(later + MESSAGE_WAKE_GAP_MS);
    assert!(text_wakes(&mut bob).is_empty(), "nothing new was queued");

    send(&mut bob, "third");
    bob.drain_inbound_at(later + MESSAGE_WAKE_GAP_MS / 2);
    assert!(text_wakes(&mut bob).is_empty(), "too soon after the last");
    bob.drain_inbound_at(later + MESSAGE_WAKE_GAP_MS);
    assert_eq!(text_wakes(&mut bob), vec![text_wake]);
}

// A phone that just went to sleep stays Connected for the lost window, so a
// text sent then goes out unacknowledged instead of queued; it must wake the
// phone all the same.
#[test]
fn an_unacknowledged_text_wakes_a_device_that_went_away() {
    let (net, _alice, mut bob, session_id) = announced_pair();
    bob.send_message(&session_id, "hi".to_string())
        .expect("a text for a connected peer goes out");
    net.link_both(ALICE_ID, BOB_ID, PeerTransport::None);

    bob.drain_inbound_at(after_silence());

    let text_wake = WakeRequest {
        call_id: None,
        ..call_wake("")
    };
    assert_eq!(text_wakes(&mut bob), vec![text_wake]);
}

// The service answered that it no longer knows the handle.
#[test]
fn a_forgotten_handle_wakes_nothing() {
    let (net, _alice, mut bob, session_id) = announced_pair();
    net.link_both(ALICE_ID, BOB_ID, PeerTransport::None);
    bob.forget_wake_handle(HANDLE);

    bob.call_start(&session_id).expect("Bob calls");
    bob.drain_inbound_at(after_silence());

    assert!(bob.take_wake_requests().is_empty());
}

#[test]
fn the_address_survives_a_restart() {
    let mut db = std::env::temp_dir();
    db.push(format!("mosh-dm-wake-restart-{}.redb", std::process::id()));
    let _ = std::fs::remove_file(&db);
    let persistence = Arc::new(
        crate::persistence::Persistence::open_with_dek(&db, [5u8; 32]).expect("store opens"),
    );
    let net = MemoryNet::new();
    net.link_both(ALICE_ID, BOB_ID, PeerTransport::Direct);
    let mut alice = PrivateDmRuntime::with_transport(net.endpoint(ALICE_ID), temp_store(), None);
    alice.set_wake_address(address(HANDLE));
    let session_id = {
        let mut bob = PrivateDmRuntime::with_transport(
            net.endpoint(BOB_ID),
            temp_store(),
            Some(Arc::clone(&persistence)),
        );
        let invite = invite(&mut alice);
        accept(&mut bob, &invite);
        connect(&mut alice, &mut bob, &invite.session_id);
        exchange(&mut alice, &mut bob, &invite.session_id);
        bob.drain_inbound_at(now_ms());
        invite.session_id
    };
    net.link_both(ALICE_ID, BOB_ID, PeerTransport::None);

    let mut bob =
        PrivateDmRuntime::with_transport(net.endpoint(BOB_ID), temp_store(), Some(persistence));
    bob.set_wake_service(SERVICE.to_string());
    bob.rehydrate();
    let call = bob
        .call_start(&session_id)
        .expect("Bob calls after the restart");
    bob.drain_inbound_at(after_silence());

    assert_eq!(bob.take_wake_requests(), vec![call_wake(&call.call_id)]);
    drop(bob);
    let _ = std::fs::remove_file(&db);
}

pub(crate) fn announcement(handle: &str, service: &str, issued_at_ms: u64) -> WakeAnnouncement {
    WakeAnnouncement {
        wake_address: WakeAddress {
            service: service.to_string(),
            handle: handle.to_string(),
        },
        issued_at_ms,
        preview_key: None,
    }
}

// A replayed older frame must not bring back a handle the device replaced
// or withdrew.
#[test]
fn only_a_newer_announcement_replaces_the_held_one() {
    let mut book = WakeBook::default();
    assert!(book.accept("signer".into(), announcement(HANDLE, SERVICE, 2)));
    assert!(!book.accept("signer".into(), announcement("", SERVICE, 1)));
    assert!(!book.accept("signer".into(), announcement("", SERVICE, 2)));
    assert!(book.accept("signer".into(), announcement("", SERVICE, 3)));
}

// The address turns into an HTTP request on the receiving device.
#[test]
fn an_address_off_the_service_shape_is_refused() {
    let mut book = WakeBook::default();
    assert!(!book.accept("a".into(), announcement(HANDLE, "http://wake.example", 1)));
    assert!(!book.accept("b".into(), announcement("short", SERVICE, 1)));
    let long = format!("https://{}", "w".repeat(SERVICE_MAX_LEN));
    assert!(!book.accept("c".into(), announcement(HANDLE, &long, 1)));
    assert!(!book.accept(
        "d".into(),
        announcement(HANDLE, "https://wake.example/a b", 1)
    ));
}
