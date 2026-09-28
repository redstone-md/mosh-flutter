use super::*;

#[test]
fn real_removed_installation_gets_no_history_or_epoch_offer_for_old_or_fresh_signed_requests() {
    let _network = isolated_network_scenario();
    let (mut original, mut contact, mut linked, session) =
        dm_recovery::linked_dm(Peer::new_manual_dm());
    let root = original.ask(json!({"action":"network"}))["public_key"].clone();
    let other = contact.ask(json!({"action":"network"}))["public_key"].clone();
    let mut captures = Vec::new();
    let epoch = linked.ask(json!({"action":"crypto_status", "argument":session}))["epoch"].clone();
    for (kind, peer) in [
        ("history", root.clone()),
        ("recovery", other),
        ("recovery_pull", root),
    ] {
        let id = format!("native-before-removal-{kind}");
        let request = linked.ask(json!({"action":"protocol_capture", "argument":session, "kind":kind, "request_id":id, "recipient":peer, "epoch":epoch}));
        let id = request["request_id"].as_str().unwrap().to_owned();
        linked.ask(json!({"action":"protocol_send", "argument":peer, "packet":request["packet"]}));
        let response = read_until(&mut linked, &id);
        assert!(
            !response.as_array().unwrap().is_empty(),
            "positive control must reach a real authorized source"
        );
        captures.push((kind, peer, id, request));
    }
    let target = linked.ask(json!({"action":"snapshot"}))["own_device_id"].clone();
    original.ask(json!({"action":"revoke", "argument":target}));
    wait_applied(&mut original, &mut contact, &session);
    let until = Instant::now() + Duration::from_secs(30);
    while linked.ask(json!({"action":"snapshot"}))["revoked"] != true {
        assert!(Instant::now() < until);
        std::thread::sleep(Duration::from_millis(100));
    }
    send(&mut original, &session, "Fresh protected history");
    contact.wait_dm_text(&session, "Fresh protected history");
    for (kind, peer, id, request) in captures {
        // Discard replies to the positive control before replaying it. Those
        // replies were authorized and may still be queued in the manual worker.
        linked.ask(json!({"action":"protocol_read", "request_id":id}));
        linked.ask(json!({"action":"protocol_send", "argument":peer, "packet":request["packet"]}));
        assert_silent(&mut linked, &id);
        let kind = if kind == "history" {
            "recovery_pull"
        } else {
            kind
        };
        let id = format!("native-after-removal-{kind}");
        let epoch =
            original.ask(json!({"action":"crypto_status", "argument":session}))["epoch"].clone();
        let fresh = linked.ask(json!({"action":"protocol_capture", "argument":session, "kind":kind, "request_id":id, "recipient":peer, "roster":request["roster"], "epoch":epoch}));
        linked.ask(json!({"action":"protocol_send", "argument":peer, "packet":fresh["packet"]}));
        assert_silent(&mut linked, &id);
    }
    let archive = linked.ask(json!({"action":"dm_poll", "argument":session}));
    assert_eq!(archive["device_revocation"], "revoked");
    assert!(!archive["messages"]
        .as_array()
        .unwrap()
        .iter()
        .any(|m| m["body"] == "Fresh protected history"));
}

fn read_until(peer: &mut Peer, id: &str) -> Value {
    let until = Instant::now() + Duration::from_secs(15);
    loop {
        let response = peer.ask(json!({"action":"protocol_read", "request_id":id}));
        if !response.as_array().unwrap().is_empty() {
            return response;
        }
        assert!(
            Instant::now() < until,
            "source must answer an authorized {id}"
        );
        std::thread::sleep(Duration::from_millis(100));
    }
}

fn assert_silent(peer: &mut Peer, id: &str) {
    let until = Instant::now() + Duration::from_secs(2);
    while Instant::now() < until {
        let response = peer.ask(json!({"action":"protocol_read", "request_id":id}));
        assert!(
            response.as_array().unwrap().is_empty(),
            "revoked {id} must produce no history or epoch response: {response}"
        );
        std::thread::sleep(Duration::from_millis(100));
    }
}
