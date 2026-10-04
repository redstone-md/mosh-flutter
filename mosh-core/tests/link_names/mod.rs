//! Caller-visible name synchronization through independent native installations.
use super::link_support::{isolated_network_scenario, Peer};
use serde_json::{json, Value};
use std::time::{Duration, Instant};

#[test]
fn personal_names_sync_after_link_and_offline_reset_survives_both_restarts() {
    let _network = isolated_network_scenario();
    let mut trusted = Peer::new();
    let mut joining = Peer::new();
    joining
        .ask(json!({"action":"name_set","argument":"channel:old-installation","name":"Old user"}));
    trusted.ask(json!({"action":"name_set","argument":"channel:general","name":"Работа"}));
    trusted.connect(&joining);
    let qr = trusted.ask(json!({"action":"qr"}));
    joining.ask(json!({"action":"import","argument":qr["qr_uri"],"name":"Second desktop"}));
    trusted.wait_phase("AwaitingApproval");
    let code = joining.wait_phase("AwaitingConfirmation")["confirmation_code"].clone();
    trusted.ask(json!({"action":"approve","argument":code}));
    joining.wait_phase("Linked");
    trusted.wait_phase("Linked");
    assert_eq!(
        wait_name(&mut joining, "channel:general", Some("Работа")),
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
