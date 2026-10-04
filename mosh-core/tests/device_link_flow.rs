mod link_names;
mod link_revocation;
mod link_support;

use link_support::{isolated_network_scenario, peer_process, Peer};
use serde_json::json;

#[test]
fn an_offline_pairing_target_does_not_block_link_commands() {
    let _network = isolated_network_scenario();
    let mut trusted = Peer::new();
    let mut carrier = Peer::new();
    let mut joining = Peer::new();
    let carrier_id =
        carrier.ask(json!({"action":"snapshot"}))["devices"][0]["moss_peer_id"].clone();
    joining.connect(&carrier);
    let until = std::time::Instant::now() + std::time::Duration::from_secs(10);
    loop {
        let network = joining.ask(json!({"action":"network"}));
        if network["peer_details"]
            .as_array()
            .unwrap()
            .iter()
            .any(|peer| peer["id"] == carrier_id)
        {
            break;
        }
        assert!(std::time::Instant::now() < until, "carrier must connect");
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    let qr = trusted.ask(json!({"action":"qr"}));
    trusted.crash();
    carrier.crash();

    let started = std::time::Instant::now();
    let pending = joining.ask(json!({"action":"import","argument":qr["qr_uri"]}));
    assert!(
        started.elapsed() < std::time::Duration::from_secs(2),
        "pairing discovery must retry outside the link command, elapsed {:?}",
        started.elapsed()
    );
    assert_eq!(pending["phase"], "Connecting");
    assert_eq!(pending["devices"].as_array().unwrap().len(), 1);
    joining.ask(json!({"action":"cancel"}));
    assert_eq!(joining.ask(json!({"action":"snapshot"}))["phase"], "Failed");
}

#[test]
fn two_independent_desktops_link_only_after_trusted_approval() {
    let _network = isolated_network_scenario();
    let mut trusted = Peer::new();
    let mut joining = Peer::new();
    let before = trusted.ask(json!({"action":"snapshot"}));
    let original = joining.ask(json!({"action":"snapshot"}));
    assert_ne!(before["user_id"], original["user_id"]);
    trusted.connect(&joining);
    let qr = trusted.ask(json!({"action":"qr"}));
    assert_eq!(qr["role"], "Authorizing");
    assert_eq!(qr["own_device_id"], before["own_device_id"]);
    assert!(qr["confirmation_code"].is_null());
    let scanning =
        joining.ask(json!({"action":"import","argument":qr["qr_uri"],"name":"Second desktop"}));
    assert_eq!(scanning["role"], "Joining");
    assert!(scanning["qr_uri"].is_null());
    let pending = trusted.wait_phase("AwaitingApproval");
    let code = joining.wait_phase("AwaitingConfirmation")["confirmation_code"].clone();
    assert_eq!(pending["devices"].as_array().unwrap().len(), 1);
    assert_eq!(pending["pending_device"]["name"], "Second desktop");
    assert_eq!(
        trusted.ask(json!({"action":"approve","argument":"wrong"}))["error"],
        "CodeMismatch"
    );
    trusted.ask(json!({"action":"approve","argument":code}));
    let joined = joining.wait_phase("Linked");
    let approved = trusted.wait_phase("Linked");
    assert_eq!(joined["user_id"], before["user_id"]);
    assert_eq!(joined["devices"], approved["devices"]);
    assert_eq!(joined["own_device_id"], original["own_device_id"]);
    assert_eq!(approved["own_device_id"], before["own_device_id"]);
    assert_eq!(approved["devices"].as_array().unwrap().len(), 2);
    assert_eq!(
        joining.ask(json!({"action":"import","argument":qr["qr_uri"]}))["error"],
        "Ineligible"
    );
    trusted.restart();
    joining.restart();
    let restored = joining.ask(json!({"action":"snapshot"}));
    assert_eq!(restored["user_id"], joined["user_id"]);
    assert_eq!(restored["devices"], joined["devices"]);
    assert_eq!(
        trusted.ask(json!({"action":"snapshot"}))["devices"],
        approved["devices"]
    );
}

#[test]
#[ignore = "entry point spawned by the independent-installation tests"]
fn independent_installation_process() {
    peer_process();
}

#[test]
fn declining_an_outsider_and_replaying_a_qr_never_adds_a_device() {
    let _network = isolated_network_scenario();
    let mut trusted = Peer::new();
    let mut outsider = Peer::new();
    trusted.connect(&outsider);
    let qr = trusted.ask(json!({"action":"qr"}));
    outsider.ask(json!({"action":"import","argument":qr["qr_uri"],"name":"Stranger"}));
    trusted.wait_phase("AwaitingApproval");
    trusted.ask(json!({"action":"cancel"}));
    assert_eq!(outsider.wait_phase("Failed")["error"], "Rejected");
    assert_eq!(
        trusted.ask(json!({"action":"snapshot"}))["devices"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    assert_eq!(
        outsider.ask(json!({"action":"import","argument":qr["qr_uri"]}))["error"],
        "InvalidQr"
    );
    assert_eq!(trusted.ask(json!({"action":"snapshot"}))["phase"], "Failed");
    assert_eq!(
        outsider.ask(json!({"action":"snapshot"}))["devices"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    trusted.ask(json!({"action":"cancel"}));
}

#[test]
fn expired_and_substituted_qr_requests_cannot_authorize_a_device() {
    let _network = isolated_network_scenario();
    use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
    let mut trusted = Peer::new();
    let mut joining = Peer::new();
    trusted.connect(&joining);
    let qr = trusted.ask(json!({"action":"qr"}));
    let uri = qr["qr_uri"].as_str().unwrap();
    let mut contents: serde_json::Value = serde_json::from_slice(
        &URL_SAFE_NO_PAD
            .decode(uri.strip_prefix("mosh://device-link/").unwrap())
            .unwrap(),
    )
    .unwrap();
    let expired = {
        let mut value = contents.clone();
        value["expires_at"] = json!(1);
        value
    };
    let expired = encoded_qr(&expired);
    assert_eq!(
        joining.ask(json!({"action":"import","argument":expired}))["error"],
        "Expired"
    );
    contents["device"]["name"] = json!("Changed after QR creation");
    let changed = encoded_qr(&contents);
    joining.ask(json!({"action":"import","argument":changed}));
    std::thread::sleep(std::time::Duration::from_secs(1));
    assert_eq!(
        joining.ask(json!({"action":"snapshot"}))["phase"],
        "Connecting"
    );
    assert_eq!(
        trusted.ask(json!({"action":"snapshot"}))["phase"],
        "ShowingQr"
    );
    assert_eq!(
        trusted.ask(json!({"action":"approve","argument":"000000000000"}))["error"],
        "InvalidRoster"
    );
    assert_eq!(
        trusted.ask(json!({"action":"snapshot"}))["devices"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
}

fn encoded_qr(contents: &serde_json::Value) -> String {
    use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
    format!(
        "mosh://device-link/{}",
        URL_SAFE_NO_PAD.encode(serde_json::to_vec(contents).unwrap())
    )
}

#[test]
fn pairing_preserves_a_real_existing_dm_and_its_counterpart_after_restart() {
    let _network = isolated_network_scenario();
    let mut trusted = Peer::new();
    let mut counterpart = Peer::new();
    let mut joining = Peer::new();
    trusted.connect(&counterpart);
    let invite = trusted.ask(json!({"action":"dm_invite"}));
    counterpart.ask(json!({"action":"dm_accept","argument":invite["invite_uri"]}));
    let session = invite["session_id"].as_str().unwrap();
    trusted.ask(json!({"action":"dm_send","argument":session,"body":"Before linking"}));
    let old_dm = counterpart.wait_dm_text(session, "Before linking");
    assert_eq!(
        trusted.ask(json!({"action":"import","argument":"mosh://device-link/unused"}))["error"],
        "Ineligible"
    );
    let before = trusted.ask(json!({"action":"snapshot"}));
    trusted.connect(&joining);
    let qr = trusted.ask(json!({"action":"qr"}));
    joining.ask(json!({"action":"import","argument":qr["qr_uri"],"name":"Second desktop"}));
    trusted.wait_phase("AwaitingApproval");
    let code = joining.wait_phase("AwaitingConfirmation")["confirmation_code"].clone();
    trusted.ask(json!({"action":"approve","argument":code}));
    trusted.wait_phase("Linked");
    joining.wait_phase("Linked");
    trusted.restart();
    trusted.connect(&counterpart);
    assert_eq!(
        trusted.ask(json!({"action":"snapshot"}))["user_id"],
        before["user_id"]
    );
    trusted.ask(json!({"action":"dm_send","argument":session,"body":"After linking and restart"}));
    let restored_dm = counterpart.wait_dm_text(session, "After linking and restart");
    assert_eq!(restored_dm["peer_moss_id"], old_dm["peer_moss_id"]);
    assert!(restored_dm["messages"]
        .as_array()
        .unwrap()
        .iter()
        .any(|m| m["body"] == "Before linking"));
}

#[test]
fn an_interrupted_approved_link_recovers_when_both_desktops_restart() {
    let _network = isolated_network_scenario();
    let mut trusted = Peer::new();
    let mut joining = Peer::new();
    trusted.connect(&joining);
    let qr = trusted.ask(json!({"action":"qr"}));
    joining.ask(json!({"action":"import","argument":qr["qr_uri"],"name":"Second desktop"}));
    trusted.wait_phase("AwaitingApproval");
    let code = joining.wait_phase("AwaitingConfirmation")["confirmation_code"].clone();
    joining.stop();
    std::thread::sleep(std::time::Duration::from_secs(16));
    assert_eq!(
        trusted.ask(json!({"action":"snapshot"}))["error"],
        "ConnectionLost"
    );
    assert_eq!(
        trusted.ask(json!({"action":"approve","argument":code}))["phase"],
        "Delivering"
    );
    joining.restart();
    let phase = joining.ask(json!({"action":"snapshot"}))["phase"].clone();
    assert!(
        phase == "AwaitingConfirmation" || phase == "Linked",
        "must restore the authenticated request, got {phase}"
    );
    trusted.restart();
    trusted.connect(&joining);
    let restored = joining.wait_phase("Linked");
    assert_eq!(trusted.wait_phase("Linked")["devices"], restored["devices"]);
}

#[test]
fn public_bridge_links_independent_desktops_through_moss_discovery() {
    let _network = isolated_network_scenario();
    let mut trusted = Peer::new_api();
    let mut joining = Peer::new_api();
    let before = trusted.ask(json!({"action":"snapshot"}));
    assert_eq!(
        trusted.ask(json!({"action":"import","argument":"invalid"}))["error"],
        "InvalidQr"
    );
    joining.ask(json!({"action":"qr","argument":"Cancelled request"}));
    joining.ask(json!({"action":"cancel"}));
    let qr = trusted.ask(json!({"action":"qr"}));
    joining.ask(json!({"action":"import","argument":qr["qr_uri"],"name":"Independent desktop"}));
    trusted.wait_phase("AwaitingApproval");
    let code = joining.wait_phase("AwaitingConfirmation")["confirmation_code"].clone();
    assert_eq!(
        trusted.ask(json!({"action":"approve","argument":"wrong"}))["error"],
        "CodeMismatch"
    );
    trusted.ask(json!({"action":"approve","argument":code}));
    let joined = joining.wait_phase("Linked");
    assert_eq!(trusted.wait_phase("Linked")["devices"], joined["devices"]);
    assert_eq!(joined["user_id"], before["user_id"]);
    assert_eq!(joined["devices"].as_array().unwrap().len(), 2);
    joining.restart();
    let restored = joining.ask(json!({"action":"snapshot"}));
    assert!(
        restored["error"].is_null(),
        "restarted bridge snapshot failed: {}",
        restored["error"]
    );
    assert_eq!(restored["devices"], joined["devices"]);
}

#[test]
fn cancelling_while_the_joining_desktop_is_offline_consumes_the_qr_after_restart() {
    let _network = isolated_network_scenario();
    let mut trusted = Peer::new();
    let mut joining = Peer::new();
    trusted.connect(&joining);
    let qr = trusted.ask(json!({"action":"qr"}));
    joining.ask(json!({"action":"import","argument":qr["qr_uri"],"name":"Offline desktop"}));
    trusted.wait_phase("AwaitingApproval");
    joining.wait_phase("AwaitingConfirmation");
    joining.stop();
    trusted.ask(json!({"action":"cancel"}));
    trusted.restart();
    joining.restart();
    trusted.connect(&joining);
    assert_eq!(
        trusted.ask(json!({"action":"import","argument":qr["qr_uri"]}))["error"],
        "InvalidQr"
    );
    assert_eq!(
        trusted.ask(json!({"action":"snapshot"}))["devices"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    assert_eq!(
        joining.ask(json!({"action":"snapshot"}))["devices"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
}

#[test]
fn a_new_dm_during_pairing_preserves_identity_and_clears_the_ineligible_request() {
    let _network = isolated_network_scenario();
    let mut trusted = Peer::new();
    let mut joining = Peer::new();
    trusted.connect(&joining);
    let before = joining.ask(json!({"action":"snapshot"}));
    let qr = trusted.ask(json!({"action":"qr"}));
    joining.ask(json!({"action":"import","argument":qr["qr_uri"],"name":"New desktop"}));
    trusted.wait_phase("AwaitingApproval");
    let code = joining.wait_phase("AwaitingConfirmation")["confirmation_code"].clone();
    let invite = joining.ask(json!({"action":"dm_invite"}));
    assert_eq!(joining.wait_phase("Failed")["error"], "Ineligible");
    assert_eq!(trusted.wait_phase("Failed")["error"], "Rejected");
    assert_eq!(
        trusted.ask(json!({"action":"approve","argument":code}))["error"],
        "InvalidRoster"
    );
    assert_eq!(
        trusted.ask(json!({"action":"snapshot"}))["devices"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    joining.restart();
    let restored = joining.ask(json!({"action":"snapshot"}));
    assert_eq!(restored["user_id"], before["user_id"]);
    assert_eq!(restored["own_device_id"], before["own_device_id"]);
    assert_eq!(restored["can_join"], false);
    assert!(restored["qr_uri"].is_null());
    assert!(restored["confirmation_code"].is_null());
    joining.ask(json!({"action":"cancel"}));
    joining.restart();
    assert_eq!(joining.ask(json!({"action":"snapshot"}))["phase"], "Idle");
    assert_eq!(
        joining.ask(json!({"action":"dm_poll","argument":invite["session_id"]}))["session_id"],
        invite["session_id"]
    );
}
