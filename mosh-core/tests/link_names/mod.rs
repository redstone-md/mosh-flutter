//! Caller-visible name synchronization through independent native installations.
use super::link_support::{isolated_network_scenario, Peer};
use serde_json::{json, Value};
use std::time::{Duration, Instant};

fn link_with_names(trusted: &mut Peer, joining: &mut Peer) {
    joining
        .ask(json!({"action":"name_set","argument":"channel:old-installation","name":"Old user"}));
    trusted.ask(json!({"action":"name_set","argument":"channel:general","name":"Работа"}));
    for n in 0..18 {
        trusted.ask(json!({"action":"name_set","argument":format!("channel:page-{n:02}"),"name":format!("Page {n}")}));
    }
    trusted.connect(joining);
    let qr = trusted.ask(json!({"action":"qr"}));
    joining.ask(json!({"action":"import","argument":qr["qr_uri"],"name":"Second desktop"}));
    trusted.wait_phase("AwaitingApproval");
    let code = joining.wait_phase("AwaitingConfirmation")["confirmation_code"].clone();
    trusted.ask(json!({"action":"approve","argument":code}));
    joining.wait_phase("Linked");
    trusted.wait_phase("Linked");
    assert_eq!(
        wait_name(joining, "channel:general", Some("Работа")),
        Some("Работа".into())
    );
    assert_eq!(
        name(
            &joining.ask(json!({"action":"names"})),
            "channel:old-installation"
        ),
        None
    );
    assert_eq!(
        name(
            &trusted.ask(json!({"action":"names"})),
            "channel:old-installation"
        ),
        None
    );
    assert_eq!(
        wait_name(joining, "channel:page-17", Some("Page 17")),
        Some("Page 17".into())
    );
}

#[test]
fn personal_names_sync_after_link_and_offline_reset_survives_both_restarts() {
    let _network = isolated_network_scenario();
    let mut trusted = Peer::new();
    let mut joining = Peer::new();
    link_with_names(&mut trusted, &mut joining);
    let root_device = trusted.ask(json!({"action":"snapshot"}))["own_device_id"]
        .as_str()
        .unwrap()
        .to_owned();
    let other_device = joining.ask(json!({"action":"snapshot"}))["own_device_id"]
        .as_str()
        .unwrap()
        .to_owned();
    joining.stop();
    trusted.ask(json!({"action":"name_set","argument":"channel:general","name":"Alpha"}));
    trusted.stop();
    joining.restart();
    joining.ask(json!({"action":"name_set","argument":"channel:general","name":"Beta"}));
    joining.stop();
    trusted.restart();
    joining.restart();
    trusted.connect(&joining);
    let winner = if root_device > other_device {
        "Alpha"
    } else {
        "Beta"
    };
    wait_name(&mut joining, "channel:general", Some(winner));
    wait_name(&mut trusted, "channel:general", Some(winner));
    joining.stop();
    trusted.ask(json!({"action":"name_reset","argument":"channel:general"}));
    trusted.restart();
    joining.restart();
    trusted.connect(&joining);
    assert_eq!(wait_name(&mut joining, "channel:general", None), None);
    assert_eq!(
        name(&trusted.ask(json!({"action":"names"})), "channel:general"),
        None
    );
    assert_revoked_writer_is_denied(&mut trusted, &mut joining, &other_device);
}

fn assert_revoked_writer_is_denied(trusted: &mut Peer, joining: &mut Peer, device: &str) {
    trusted.ask(json!({"action":"revoke","argument":device}));
    let until = Instant::now() + Duration::from_secs(30);
    while joining.ask(json!({"action":"snapshot"}))["revoked"] != true {
        assert!(Instant::now() < until, "revocation did not arrive");
        std::thread::sleep(Duration::from_millis(100));
    }
    assert_eq!(
        joining.ask(json!({"action":"name_set","argument":"channel:general","name":"Revoked"}))
            ["error"],
        "Unauthorized"
    );
}

#[test]
fn public_bridge_saves_and_resets_personal_names_across_restart() {
    let _network = isolated_network_scenario();
    let mut peer = Peer::new_api();
    for key in ["dm:stable-session", "channel:canonical-address"] {
        let accepted = peer.ask(json!({"action":"name_set","argument":key,"name":" Personal "}));
        assert_eq!(name(&accepted, key).as_deref(), Some("Personal"));
    }
    peer.restart();
    assert_eq!(
        name(&peer.ask(json!({"action":"names"})), "dm:stable-session").as_deref(),
        Some("Personal")
    );
    assert_eq!(
        peer.ask(json!({"action":"name_set","argument":"dm:stable-session","name":""}))["error"],
        "InvalidInput"
    );
    assert_eq!(
        peer.ask(json!({"action":"name_reset","argument":"group:any"}))["error"],
        "InvalidInput"
    );
    assert_eq!(
        name(
            &peer.ask(json!({"action":"name_reset","argument":"dm:stable-session"})),
            "dm:stable-session"
        ),
        None
    );
}

fn name(snapshot: &Value, key: &str) -> Option<String> {
    snapshot["entries"]
        .as_array()
        .unwrap()
        .iter()
        .find(|entry| entry["conversation_key"] == key)
        .map(|entry| entry["name"].as_str().unwrap().to_owned())
}

fn wait_name(peer: &mut Peer, key: &str, expected: Option<&str>) -> Option<String> {
    let until = Instant::now() + Duration::from_secs(30);
    loop {
        let snapshot = peer.ask(json!({"action":"names"}));
        let actual = name(&snapshot, key);
        if actual.as_deref() == expected {
            return actual;
        }
        assert!(Instant::now() < until, "name did not converge: {snapshot}");
        std::thread::sleep(Duration::from_millis(100));
    }
}
