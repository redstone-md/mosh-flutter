use super::*;
use std::time::{Duration, Instant};

#[test]
fn removal_is_durable_and_old_qr_cannot_restore_the_linked_installation() {
    let _network = isolated_network_scenario();
    let mut trusted = Peer::new();
    let mut linked = Peer::new();
    trusted.connect(&linked);
    let qr = linked.ask(json!({"action":"qr","argument":"Removed desktop"}));
    trusted.ask(json!({"action":"import","argument":qr["qr_uri"]}));
    trusted.wait_phase("AwaitingApproval");
    let code = linked.wait_phase("AwaitingConfirmation")["confirmation_code"].clone();
    trusted.ask(json!({"action":"approve","argument":code}));
    trusted.wait_phase("Linked");
    let before = linked.wait_phase("Linked");
    let removed = trusted.ask(json!({"action":"revoke","argument":before["own_device_id"]}));
    assert_eq!(removed["devices"].as_array().unwrap().len(), 1);
    assert_eq!(removed["revocations"][0]["state"], "Applied");
    let until = Instant::now() + Duration::from_secs(30);
    loop {
        let snapshot = linked.ask(json!({"action":"snapshot"}));
        if snapshot["revoked"] == true {
            assert_eq!(snapshot["user_id"], before["user_id"]);
            assert_eq!(snapshot["own_device_id"], before["own_device_id"]);
            assert_eq!(snapshot["devices"], removed["devices"]);
            break;
        }
        assert!(
            Instant::now() < until,
            "revocation must reach the installation"
        );
        std::thread::sleep(Duration::from_millis(100));
    }
    trusted.restart();
    linked.restart();
    assert_eq!(linked.ask(json!({"action":"snapshot"}))["revoked"], true);
    assert_eq!(
        trusted.ask(json!({"action":"snapshot"}))["devices"],
        removed["devices"]
    );
    assert_eq!(
        trusted.ask(json!({"action":"import","argument":qr["qr_uri"]}))["error"],
        "InvalidQr"
    );
    assert_eq!(
        linked.ask(json!({"action":"import","argument":qr["qr_uri"]}))["error"],
        "InvalidRoster"
    );
    let fresh = linked.ask(json!({"action":"qr","argument":"Fresh authorization"}));
    assert_eq!(
        fresh["user_id"], before["user_id"],
        "retained identity must stay pinned until fresh permission"
    );
    assert_eq!(fresh["revoked"], true);
    trusted.connect(&linked);
    trusted.ask(json!({"action":"import","argument":fresh["qr_uri"]}));
    trusted.wait_phase("AwaitingApproval");
    let code = linked.wait_phase("AwaitingConfirmation")["confirmation_code"].clone();
    assert_eq!(linked.ask(json!({"action":"snapshot"}))["revoked"], true);
    assert_eq!(
        trusted.ask(json!({"action":"snapshot"}))["devices"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    trusted.ask(json!({"action":"approve","argument":code}));
    let authorized = linked.wait_phase("Linked");
    trusted.wait_phase("Linked");
    assert_eq!(authorized["revoked"], false);
    assert_eq!(authorized["user_id"], before["user_id"]);
    assert_eq!(authorized["own_device_id"], before["own_device_id"]);
    assert_eq!(authorized["devices"].as_array().unwrap().len(), 2);
    assert_eq!(
        trusted.ask(json!({"action":"import","argument":qr["qr_uri"]}))["error"],
        "InvalidQr"
    );
}
