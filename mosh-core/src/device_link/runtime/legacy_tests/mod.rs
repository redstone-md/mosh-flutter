mod fixture;
#[path = "../../../../tests/link_support/mod.rs"]
#[allow(
    dead_code,
    reason = "Only the migration subset of the shared process harness is needed here"
)]
mod link_support;

use link_support::{isolated_network_scenario, Peer};
use serde_json::json;

#[test]
#[ignore = "independent installation used by the legacy migration test"]
fn legacy_worker() {
    link_support::peer_process_with(|store, action, value| {
        action
            .starts_with("legacy_")
            .then(|| fixture::command(store, action, value))
    });
}

#[test]
fn an_already_approved_v1_delivery_and_receipt_finish_after_upgrade() {
    let _network = isolated_network_scenario();
    let mut trusted = Peer::new_with_worker("device_link::runtime::legacy_tests::legacy_worker");
    let mut joining = Peer::new_with_worker("device_link::runtime::legacy_tests::legacy_worker");
    let trusted_before = trusted.ask(json!({"action":"snapshot"}));
    let joining_before = joining.ask(json!({"action":"snapshot"}));
    let qr = joining.ask(json!({"action":"legacy_qr"}));
    // v1 stored the authenticated base before the authorizer committed approval.
    let base = trusted.ask(json!({"action":"legacy_base"}));
    joining.ask(json!({"action":"legacy_pending", "qr":qr,
        "trusted":trusted_before["devices"][0], "base":base
    }));
    trusted.ask(json!({"action":"legacy_approved", "qr":qr, "base":base}));
    trusted.restart();
    joining.restart();
    trusted.connect(&joining);
    let linked = joining.wait_phase("Linked");
    assert_eq!(trusted.wait_phase("Linked")["devices"], linked["devices"]);
    assert_eq!(linked["user_id"], trusted_before["user_id"]);
    assert_eq!(linked["own_device_id"], joining_before["own_device_id"]);
    assert_eq!(linked["devices"].as_array().unwrap().len(), 2);
    assert_eq!(linked["devices"][0], trusted_before["devices"][0]);
    assert_eq!(linked["devices"][1], joining_before["devices"][0]);
    // Simulate an old journal restored before its durable-save acknowledgement.
    trusted.ask(json!({"action":"legacy_approved", "qr":qr, "base":base}));
    trusted.restart();
    joining.restart();
    trusted.connect(&joining);
    assert_eq!(trusted.wait_phase("Linked")["devices"], linked["devices"]);
    assert_eq!(
        joining.ask(json!({"action":"snapshot"}))["devices"],
        linked["devices"]
    );
}
