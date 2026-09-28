use super::*;

fn wait_typing(peer: &mut Peer, session: &str) -> Value {
    let until = Instant::now() + Duration::from_secs(10);
    loop {
        let snapshot = peer.ask(json!({"action":"dm_poll","argument":session}));
        if snapshot["peer_typing_until_ms"].is_number() {
            return snapshot;
        }
        assert!(Instant::now() < until, "real contact typing must arrive");
        std::thread::sleep(Duration::from_millis(100));
    }
}

fn assert_contact_stays_offline(peer: &mut Peer, session: &str, contact_peer: &Value) {
    let until = Instant::now() + Duration::from_secs(2);
    while Instant::now() < until {
        let snapshot = peer.ask(json!({"action":"dm_poll","argument":session}));
        assert_eq!(
            snapshot["state"], "handshaking",
            "a sibling cannot prove contact liveness"
        );
        assert!(
            snapshot["peer_typing_until_ms"].is_null(),
            "a sibling is not contact typing"
        );
        assert_eq!(snapshot["peer_display_name"], "Counterpart");
        assert_eq!(&snapshot["peer_moss_id"], contact_peer);
        std::thread::sleep(Duration::from_millis(100));
    }
}

fn wait_read(peer: &mut Peer, session: &str, body: &str) {
    let until = Instant::now() + Duration::from_secs(10);
    loop {
        let snapshot = peer.ask(json!({"action":"dm_poll","argument":session}));
        if snapshot["messages"]
            .as_array()
            .unwrap()
            .iter()
            .any(|message| message["body"] == body && message["read"] == true)
        {
            return;
        }
        assert!(
            Instant::now() < until,
            "the contact's read receipt must reach both desktops"
        );
        std::thread::sleep(Duration::from_millis(100));
    }
}

#[test]
fn sibling_controls_cannot_make_an_offline_contact_connected_or_typing() {
    let _network = isolated_network_scenario();
    let mut original = Peer::new();
    let mut counterpart = Peer::new();
    let mut linked = Peer::new();
    let invite = existing_dm(&mut original, &mut counterpart);
    let session = invite["session_id"].as_str().unwrap();
    pair(&mut original, &mut linked);
    linked.connect(&counterpart);
    wait_connected(&mut linked, &mut counterpart, session);
    send(&mut counterpart, session, "Read later on sibling");
    original.wait_dm_text(session, "Read later on sibling");
    linked.wait_dm_text(session, "Read later on sibling");
    for peer in [&mut original, &mut linked, &mut counterpart] {
        peer.ask(json!({"action":"dm_receipts","enabled":true}));
    }
    send(&mut original, session, "Contact reads shared text");
    counterpart.wait_dm_text(session, "Contact reads shared text");
    linked.wait_dm_text(session, "Contact reads shared text");
    counterpart.ask(json!({"action":"dm_viewed","argument":session}));
    wait_read(&mut original, session, "Contact reads shared text");
    wait_read(&mut linked, session, "Contact reads shared text");
    counterpart.ask(json!({"action":"dm_typing","argument":session}));
    let contact_peer = wait_typing(&mut original, session)["peer_moss_id"].clone();
    wait_typing(&mut linked, session);
    counterpart.stop();
    let until = Instant::now() + Duration::from_secs(35);
    loop {
        let snapshot = original.ask(json!({"action":"dm_poll","argument":session}));
        if snapshot["state"] == "handshaking" && snapshot["peer_typing_until_ms"].is_null() {
            break;
        }
        assert!(
            Instant::now() < until,
            "the stopped contact must become offline"
        );
        std::thread::sleep(Duration::from_millis(100));
    }
    linked.ask(json!({"action":"dm_typing","argument":session}));
    assert_contact_stays_offline(&mut original, session, &contact_peer);
    linked.ask(json!({"action":"dm_viewed","argument":session}));
    assert_contact_stays_offline(&mut original, session, &contact_peer);
}
