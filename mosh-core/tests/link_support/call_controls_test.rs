use super::link_support::{isolated_network_scenario, Peer};
use serde_json::json;

#[test]
fn rejected_call_start_keeps_the_api_peer_available() {
    let _network = isolated_network_scenario();
    let mut peer = Peer::new_api();
    let result = peer.ask(json!({"action":"call_start", "argument":"missing-session"}));
    assert_eq!(result["error"], "MissingConversation");
    assert!(peer.ask(json!({"action":"snapshot"}))["devices"].is_array());
}
