use super::*;

#[test]
fn a_lost_saved_contact_backs_off_hello_publications() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    net.unlist(ALICE_ID, BOB_ID);
    net.endpoint(BOB_ID).drain();
    let start = now_ms() + LOST_WINDOW_MS;
    let mut hellos = 0;
    for offset in (0..=120_000).step_by(2000) {
        alice.drain_inbound_at(start + offset);
        hellos += net
            .endpoint(BOB_ID)
            .drain()
            .iter()
            .filter(|frame| payload_says(&frame.payload, "\"type\":\"Hello\""))
            .count();
    }
    assert!(
        (1..=9).contains(&hellos),
        "an established offline contact should receive at most nine probes in two minutes; got {hellos}"
    );
    assert_eq!(
        state_of(&mut alice, &invite.session_id),
        DmSessionState::Handshaking
    );
}

#[test]
fn a_restored_completed_dm_backs_off_without_claiming_presence() {
    let directory = crate::test_temp_directory::TempDirectory::new("mosh-idle-restore");
    let store = Arc::new(
        Persistence::open_with_dek(&directory.path().join("history.redb"), [57; 32]).unwrap(),
    );
    let net = MemoryNet::new();
    net.link_both(ALICE_ID, BOB_ID, PeerTransport::Direct);
    let mut alice =
        PrivateDmRuntime::with_transport(net.endpoint(ALICE_ID), temp_store(), Some(store.clone()));
    let mut bob = runtime_on(&net, BOB_ID);
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    alice
        .send_message(&invite.session_id, "saved".into())
        .unwrap();
    bob.poll_session(&invite.session_id).unwrap();
    alice.poll_session(&invite.session_id).unwrap();
    drop(alice);
    net.unlist(ALICE_ID, BOB_ID);
    let mut restored =
        PrivateDmRuntime::with_transport(net.endpoint(ALICE_ID), temp_store(), Some(store));
    restored.rehydrate();
    net.endpoint(BOB_ID).drain();
    let start = now_ms();
    let mut hellos = 0;
    for offset in (0..=120_000).step_by(2000) {
        restored.drain_inbound_at(start + offset);
        hellos += net
            .endpoint(BOB_ID)
            .drain()
            .iter()
            .filter(|frame| payload_says(&frame.payload, "\"type\":\"Hello\""))
            .count();
    }
    assert!(
        (1..=9).contains(&hellos),
        "restored DM sent {hellos} probes"
    );
    assert_eq!(
        state_of(&mut restored, &invite.session_id),
        DmSessionState::Handshaking
    );
}

#[test]
fn a_new_transport_path_wakes_a_backed_off_probe_without_faking_presence() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    let start = now_ms() + LOST_WINDOW_MS;
    alice.drain_inbound_at(start);
    alice.drain_inbound_at(start + 2000);
    net.endpoint(BOB_ID).drain();
    net.link(ALICE_ID, BOB_ID, PeerTransport::Relayed);
    alice.drain_inbound_at(start + 2001);
    assert!(
        net.endpoint(BOB_ID)
            .drain()
            .iter()
            .any(|frame| { payload_says(&frame.payload, "\"type\":\"Hello\"") }),
        "a newly available path must not wait for the idle retry deadline"
    );
    let snapshot = alice.poll_session(&invite.session_id).unwrap();
    assert_eq!(snapshot.transport, PeerTransport::Relayed);
    assert_eq!(snapshot.state, DmSessionState::Handshaking);
}

#[test]
fn new_user_text_wakes_a_backed_off_presence_probe() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    let start = now_ms() + LOST_WINDOW_MS;
    alice.drain_inbound_at(start);
    alice.drain_inbound_at(start + 2000);
    net.endpoint(BOB_ID).drain();
    alice
        .send_message(&invite.session_id, "new user text".into())
        .unwrap();
    assert!(
        net.endpoint(BOB_ID)
            .drain()
            .iter()
            .any(|frame| { payload_says(&frame.payload, "\"type\":\"Hello\"") }),
        "a newly admitted text must wake presence without waiting for the idle deadline"
    );
    assert_eq!(
        state_of(&mut alice, &invite.session_id),
        DmSessionState::Handshaking
    );
}

#[test]
fn initial_negotiation_retains_fast_hello_retries() {
    let (net, mut alice, mut bob) = memory_pair();
    net.drop_frames(BOB_ID, ALICE_ID, |_, bytes| payload_says(bytes, "Hello"));
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    alice.poll_session(&invite.session_id).unwrap();
    bob.poll_session(&invite.session_id).unwrap();
    net.endpoint(BOB_ID).drain();
    let start = now_ms();
    let mut probes = 0;
    for offset in (0..=20_000).step_by(2000) {
        alice.drain_inbound_at(start + offset);
        probes += net
            .endpoint(BOB_ID)
            .drain()
            .iter()
            .filter(|frame| payload_says(&frame.payload, "\"type\":\"Hello\""))
            .count();
    }
    assert!(
        (10..=11).contains(&probes),
        "initial negotiation sent {probes} probes"
    );
    assert_eq!(
        state_of(&mut alice, &invite.session_id),
        DmSessionState::Handshaking
    );
}

#[test]
fn connected_keepalive_retains_its_existing_cadence() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    net.endpoint(BOB_ID).drain();
    let start = now_ms();
    let mut probes = 0;
    for offset in (0..=20_000).step_by(2000) {
        alice.drain_inbound_at(start + offset);
        probes += net
            .endpoint(BOB_ID)
            .drain()
            .iter()
            .filter(|frame| payload_says(&frame.payload, "\"type\":\"Hello\""))
            .count();
    }
    assert_eq!(
        probes, 2,
        "quiet connected DMs keep one probe per ten seconds"
    );
    assert_eq!(
        state_of(&mut alice, &invite.session_id),
        DmSessionState::Connected
    );
}

#[test]
fn a_peer_can_authenticate_after_an_hour_of_lost_recovery_probes() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    net.drop_frames(BOB_ID, ALICE_ID, |_, _| true);
    let start = now_ms() + LOST_WINDOW_MS;
    bob.drain_inbound_at(start);
    net.endpoint(ALICE_ID).drain();
    for offset in (0..=3_600_000).step_by(2000) {
        alice.drain_inbound_at(start + offset);
        net.endpoint(BOB_ID).drain();
    }
    alice.drain_inbound_at(start + 3_630_000);
    bob.drain_inbound_at(start + 3_630_000);
    assert_eq!(
        state_of(&mut bob, &invite.session_id),
        DmSessionState::Connected
    );
}
