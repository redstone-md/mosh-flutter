#[allow(
    dead_code,
    reason = "Invitation tests use the linking subset of the shared process harness"
)]
mod link_support;

use link_support::{isolated_network_scenario, peer_process, Peer};
use serde_json::json;

#[test]
#[ignore = "entry point spawned by independent-installation tests"]
fn independent_installation_process() {
    peer_process();
}

#[test]
fn a_second_scanner_cannot_replace_the_device_waiting_for_approval() {
    let _network = isolated_network_scenario();
    let mut trusted = Peer::new_api();
    let mut intended = Peer::new_api();
    let mut other = Peer::new_api();
    let invitation = trusted.ask(json!({"action":"qr"}));
    let uri = invitation["qr_uri"].clone();
    intended.ask(json!({"action":"import","argument":uri,"name":"Intended device"}));
    let pending = trusted.wait_phase("AwaitingApproval");
    let confirmation = intended.wait_phase("AwaitingConfirmation");
    let other_before = other.ask(json!({"action":"snapshot"}));
    other.ask(json!({"action":"import","argument":uri,"name":"Other scanner"}));
    // Wait through retries rather than approving before the second scan arrives.
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(30);
    loop {
        let snapshot = other.ask(json!({"action":"snapshot"}));
        assert_eq!(snapshot["phase"], "Connecting");
        assert!(snapshot["confirmation_code"].is_null());
        if snapshot["error"] == "ConnectionLost" {
            break;
        }
        assert!(std::time::Instant::now() < deadline);
        std::thread::sleep(std::time::Duration::from_millis(100));
    }
    let still_pending = trusted.ask(json!({"action":"snapshot"}));
    assert_eq!(still_pending["pending_device"], pending["pending_device"]);
    assert_eq!(still_pending["devices"].as_array().unwrap().len(), 1);
    assert_eq!(still_pending["phase"], "AwaitingApproval");
    assert!(still_pending["qr_uri"].is_null());
    trusted.ask(json!({"action":"approve","argument":confirmation["confirmation_code"]}));
    let approved = trusted.wait_phase("Linked");
    let linked = intended.wait_phase("Linked");
    let refused = other.ask(json!({"action":"snapshot"}));
    assert_eq!(approved["devices"], linked["devices"]);
    assert_eq!(approved["devices"][1]["name"], "Intended device");
    assert_eq!(refused["user_id"], other_before["user_id"]);
    assert_eq!(refused["devices"].as_array().unwrap().len(), 1);
    assert!(refused["confirmation_code"].is_null());
    // Positive control: the same scanner can join with a fresh invitation.
    other.ask(json!({"action":"cancel"}));
    let fresh = trusted.ask(json!({"action":"qr"}));
    other.ask(json!({"action":"import","argument":fresh["qr_uri"],"name":"Other scanner"}));
    trusted.wait_phase("AwaitingApproval");
    let code = other.wait_phase("AwaitingConfirmation")["confirmation_code"].clone();
    trusted.ask(json!({"action":"approve","argument":code}));
    assert_eq!(
        other.wait_phase("Linked")["devices"]
            .as_array()
            .unwrap()
            .len(),
        3
    );
}

#[test]
fn legacy_invitation_import_is_refused_without_changing_identity() {
    let _network = isolated_network_scenario();
    use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
    let mut trusted = Peer::new_api();
    let mut joining = Peer::new_api();
    let before = joining.ask(json!({"action":"snapshot"}));
    let invitation = trusted.ask(json!({"action":"qr"}));
    let encoded = invitation["qr_uri"]
        .as_str()
        .unwrap()
        .strip_prefix("mosh://device-link/")
        .unwrap();
    let mut qr: serde_json::Value =
        serde_json::from_slice(&URL_SAFE_NO_PAD.decode(encoded).unwrap()).unwrap();
    assert_eq!(qr["version"], 2);
    assert_eq!(qr["device"]["device_id"], invitation["own_device_id"]);
    qr["version"] = json!(1);
    let legacy = format!(
        "mosh://device-link/{}",
        URL_SAFE_NO_PAD.encode(serde_json::to_vec(&qr).unwrap())
    );
    assert_eq!(
        joining.ask(json!({"action":"import","argument":legacy}))["error"],
        "InvalidQr"
    );
    let after = joining.ask(json!({"action":"snapshot"}));
    assert_eq!(after["user_id"], before["user_id"]);
    assert_eq!(after["devices"], before["devices"]);
    assert_eq!(after["phase"], "Idle");
}
