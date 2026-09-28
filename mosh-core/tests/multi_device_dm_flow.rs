mod dm_controls;
mod dm_history;
mod dm_recovery;
mod link_support;

use link_support::{isolated_network_scenario, peer_process, Peer};
use serde_json::{json, Value};
use std::time::{Duration, Instant};

fn wait_connected(peer: &mut Peer, contact: &mut Peer, session: &str) -> Value {
    let until = Instant::now() + Duration::from_secs(45);
    loop {
        contact.ask(json!({"action":"dm_poll","argument":session}));
        let list = peer.ask(json!({"action":"dm_list"}));
        if let Some(snapshot) = list["sessions"]
            .as_array()
            .unwrap()
            .iter()
            .find(|snapshot| snapshot["session_id"] == session && snapshot["state"] == "connected")
        {
            return snapshot.clone();
        }
        assert!(
            Instant::now() < until,
            "linked desktop must join the same DM and authenticate the contact, got {list}"
        );
        std::thread::sleep(Duration::from_millis(100));
    }
}

fn pair(original: &mut Peer, linked: &mut Peer) {
    original.connect(linked);
    let qr = linked.ask(json!({"action":"qr","argument":"Linked desktop"}));
    original.ask(json!({"action":"import","argument":qr["qr_uri"]}));
    original.wait_phase("AwaitingApproval");
    let code = linked.wait_phase("AwaitingConfirmation")["confirmation_code"].clone();
    original.ask(json!({"action":"approve","argument":code}));
    original.wait_phase("Linked");
    linked.wait_phase("Linked");
}

fn existing_dm(original: &mut Peer, counterpart: &mut Peer) -> Value {
    original.connect(counterpart);
    let invite = original.ask(json!({"action":"dm_invite"}));
    counterpart.ask(json!({"action":"dm_accept","argument":invite["invite_uri"]}));
    let session = invite["session_id"].as_str().unwrap();
    wait_connected(counterpart, original, session);
    counterpart.ask(json!({"action":"dm_send","argument":session,"body":"Before pairing"}));
    original.wait_dm_text(session, "Before pairing");
    invite
}

#[test]
fn linked_desktop_joins_existing_dm_and_both_receive_new_text() {
    let _network = isolated_network_scenario();
    let mut original = Peer::new();
    let mut counterpart = Peer::new();
    let mut linked = Peer::new();
    let invite = existing_dm(&mut original, &mut counterpart);
    let session = invite["session_id"].as_str().unwrap();
    pair(&mut original, &mut linked);
    linked.connect(&counterpart);
    wait_connected(&mut linked, &mut counterpart, session);
    counterpart.ask(json!({"action":"dm_send","argument":session,"body":"Both desktops"}));
    let first = original.wait_dm_text(session, "Both desktops");
    let second = linked.wait_dm_text(session, "Both desktops");
    assert_eq!(first["fingerprint"], invite["fingerprint"]);
    assert_eq!(second["fingerprint"], invite["fingerprint"]);
    assert_eq!(second["peer_display_name"], "Counterpart");
    for peer in [&mut original, &mut linked, &mut counterpart] {
        assert_eq!(
            peer.ask(json!({"action":"dm_list"}))["sessions"]
                .as_array()
                .unwrap()
                .len(),
            1
        );
    }
}

fn send(peer: &mut Peer, session: &str, body: &str) -> Value {
    peer.ask(json!({"action":"dm_send","argument":session,"body":body}))
}

#[test]
fn live_dm_keeps_one_author_for_simultaneous_sends_and_works_without_original() {
    let _network = isolated_network_scenario();
    let mut original = Peer::new();
    let mut counterpart = Peer::new();
    let mut linked = Peer::new();
    let invite = existing_dm(&mut original, &mut counterpart);
    let session = invite["session_id"].as_str().unwrap();
    pair(&mut original, &mut linked);
    linked.connect(&counterpart);
    wait_connected(&mut linked, &mut counterpart, session);
    send(&mut counterpart, session, "Ready on both");
    original.wait_dm_text(session, "Ready on both");
    linked.wait_dm_text(session, "Ready on both");
    let (first, second) = std::thread::scope(|scope| {
        let first = scope.spawn(|| send(&mut original, session, "Original sends"));
        let second = scope.spawn(|| send(&mut linked, session, "Linked sends"));
        (first.join().unwrap(), second.join().unwrap())
    });
    assert_ne!(first["message_id"], second["message_id"]);
    for peer in [&mut original, &mut linked, &mut counterpart] {
        peer.wait_dm_text(session, "Original sends");
        let snapshot = peer.wait_dm_text(session, "Linked sends");
        assert_one_author_and_copy(&snapshot, "Original sends", "Original desktop");
        assert_one_author_and_copy(&snapshot, "Linked sends", "Original desktop");
    }
    original.stop();
    send(&mut counterpart, session, "Original is off");
    linked.wait_dm_text(session, "Original is off");
    send(&mut linked, session, "Reply without original");
    counterpart.wait_dm_text(session, "Reply without original");
    linked.restart();
    linked.connect(&counterpart);
    send(&mut linked, session, "Linked restarted");
    let snapshot = counterpart.wait_dm_text(session, "Linked restarted");
    assert_one_author_and_copy(&snapshot, "Linked restarted", "Original desktop");
    counterpart.restart();
    counterpart.connect(&linked);
    send(&mut counterpart, session, "Counterpart restarted");
    let snapshot = linked.wait_dm_text(session, "Counterpart restarted");
    assert_eq!(snapshot["fingerprint"], invite["fingerprint"]);
    assert_one_author_and_copy(&snapshot, "Original sends", "Original desktop");
    assert_one_author_and_copy(&snapshot, "Linked sends", "Original desktop");
}

fn assert_one_author_and_copy(snapshot: &Value, body: &str, author: &str) {
    let copies: Vec<_> = snapshot["messages"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|message| message["body"] == body)
        .collect();
    assert_eq!(copies.len(), 1, "one row per shared id");
    assert_eq!(copies[0]["from_device"], author);
}

fn delivery(snapshot: &Value, body: &str) -> String {
    snapshot["messages"]
        .as_array()
        .unwrap()
        .iter()
        .find(|message| message["body"] == body)
        .unwrap()["delivery_status"]
        .as_str()
        .unwrap()
        .into()
}

#[test]
fn sibling_receipt_does_not_claim_delivery_and_contact_receipt_reaches_both_desktops() {
    let _network = isolated_network_scenario();
    let mut original = Peer::new();
    let mut counterpart = Peer::new_manual_dm();
    let mut linked = Peer::new();
    let invite = existing_dm(&mut original, &mut counterpart);
    let session = invite["session_id"].as_str().unwrap();
    pair(&mut original, &mut linked);
    linked.connect(&counterpart);
    wait_connected(&mut linked, &mut counterpart, session);
    send(&mut original, session, "Only sibling has acknowledged");
    let mirror = linked.wait_dm_text(session, "Only sibling has acknowledged");
    assert_eq!(delivery(&mirror, "Only sibling has acknowledged"), "sent");
    let origin = original.ask(json!({"action":"dm_poll","argument":session}));
    assert_eq!(delivery(&origin, "Only sibling has acknowledged"), "sent");
    counterpart.wait_dm_text(session, "Only sibling has acknowledged");
    for peer in [&mut original, &mut linked] {
        let until = Instant::now() + Duration::from_secs(15);
        loop {
            let snapshot = peer.ask(json!({"action":"dm_poll","argument":session}));
            assert_one_author_and_copy(
                &snapshot,
                "Only sibling has acknowledged",
                "Original desktop",
            );
            if delivery(&snapshot, "Only sibling has acknowledged") == "delivered" {
                break;
            }
            assert!(
                Instant::now() < until,
                "contact receipt must reach each desktop"
            );
            std::thread::sleep(Duration::from_millis(100));
        }
    }
}

#[test]
fn pending_join_and_admission_journal_resume_with_independent_keys_after_restart() {
    let _network = isolated_network_scenario();
    let mut original = Peer::new_manual_dm();
    let mut counterpart = Peer::new();
    let mut linked = Peer::new();
    let invite = existing_dm(&mut original, &mut counterpart);
    let session = invite["session_id"].as_str().unwrap();
    pair(&mut original, &mut linked);
    linked.connect(&counterpart);
    let until = Instant::now() + Duration::from_secs(30);
    loop {
        original.ask(json!({"action":"dm_list"}));
        let list = linked.ask(json!({"action":"dm_list"}));
        if !list["sessions"].as_array().unwrap().is_empty() {
            break;
        }
        assert!(
            Instant::now() < until,
            "must receive the real private offer"
        );
        std::thread::sleep(Duration::from_millis(100));
    }
    assert_eq!(
        linked.ask(json!({"action":"dm_poll","argument":session}))["state"],
        "pending"
    );
    linked.restart();
    linked.connect(&original);
    linked.connect(&counterpart);
    assert_eq!(
        linked.ask(json!({"action":"dm_poll","argument":session}))["state"],
        "pending"
    );
    // A public poll applies the saved KeyPackage while automatic service is paused.
    original.ask(json!({"action":"dm_poll","argument":session}));
    original.restart();
    original.connect(&counterpart);
    original.connect(&linked);
    original.ask(json!({"action":"dm_poll","argument":session}));
    send(&mut counterpart, session, "Recovered admission");
    let first = original.wait_dm_text(session, "Recovered admission");
    let second = linked.wait_dm_text(session, "Recovered admission");
    assert_eq!(first["fingerprint"], second["fingerprint"]);
    assert_one_author_and_copy(&second, "Recovered admission", "Counterpart");
    send(&mut linked, session, "Independent restored signer");
    counterpart.wait_dm_text(session, "Independent restored signer");
}

#[test]
fn public_bridge_delivers_one_dm_to_linked_desktops_through_default_discovery() {
    let _network = isolated_network_scenario();
    let mut original = Peer::new_api();
    let mut counterpart = Peer::new_api();
    let mut linked = Peer::new_api();
    let invite = existing_dm(&mut original, &mut counterpart);
    let session = invite["session_id"].as_str().unwrap();
    pair(&mut original, &mut linked);
    wait_connected(&mut linked, &mut counterpart, session);
    send(&mut counterpart, session, "Public bridge fan-out");
    original.wait_dm_text(session, "Public bridge fan-out");
    linked.wait_dm_text(session, "Public bridge fan-out");
    send(&mut linked, session, "Public bridge own sync");
    original.wait_dm_text(session, "Public bridge own sync");
    counterpart.wait_dm_text(session, "Public bridge own sync");
    original.stop();
    send(&mut counterpart, session, "Public bridge primary off");
    linked.wait_dm_text(session, "Public bridge primary off");
    linked.restart();
    send(&mut linked, session, "Public bridge restored");
    let snapshot = counterpart.wait_dm_text(session, "Public bridge restored");
    assert_one_author_and_copy(&snapshot, "Public bridge restored", "Original desktop");
    for peer in [&mut linked, &mut counterpart] {
        assert_eq!(
            peer.ask(json!({"action":"dm_list"}))["sessions"]
                .as_array()
                .unwrap()
                .len(),
            1
        );
    }
}

#[test]
#[ignore = "independent installation subprocess entry point"]
fn independent_installation_process() {
    peer_process();
}
