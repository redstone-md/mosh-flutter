pub mod worker;

use crate::link_support::Peer;
use serde_json::{json, Value};
use std::time::{Duration, Instant};

pub fn installation() -> Peer {
    Peer::new_with_worker("invitation_installation_process")
}

pub fn create(peer: &mut Peer) -> Value {
    let invite = peer.ask(json!({"action":"create"}));
    assert!(
        invite["error"].is_null(),
        "pending invitation creation succeeds"
    );
    assert!(invite["invite_uri"].is_string());
    invite
}

pub fn accept(peer: &mut Peer, invite: &Value, name: &str) {
    let joined =
        peer.ask(json!({"action":"dm_accept", "argument":invite["invite_uri"], "name":name}));
    assert!(joined["error"].is_null(), "invitation join starts");
    assert_eq!(joined["session_id"], invite["session_id"]);
}

pub fn send(peer: &mut Peer, id: &str, body: &str) {
    let accepted = peer.ask(json!({"action":"dm_send", "argument":id, "body":body}));
    assert!(accepted["error"].is_null(), "real text send is admitted");
}

pub fn poll(peer: &mut Peer, id: &str) -> Value {
    let snapshot = peer.ask(json!({"action":"dm_poll", "argument":id}));
    assert!(snapshot["error"].is_null(), "session polling succeeds");
    snapshot
}

pub fn sessions(peer: &mut Peer) -> Vec<Value> {
    peer.ask(json!({"action":"dm_list"}))["sessions"]
        .as_array()
        .unwrap()
        .clone()
}

pub fn pending(peer: &mut Peer) -> Vec<Value> {
    peer.ask(json!({"action":"pending"}))
        .as_array()
        .unwrap()
        .clone()
}

pub fn evidence(peer: &mut Peer, id: &str, reason: &str) -> Value {
    peer.ask(json!({"action":"evidence", "argument":id, "reason":reason}))
}

pub fn wait_connected(creator: &mut Peer, contact: &mut Peer, id: &str) -> (Value, Value) {
    let until = Instant::now() + Duration::from_secs(45);
    loop {
        let alice = poll(creator, id);
        let bob = poll(contact, id);
        if alice["state"] == "connected" && bob["state"] == "connected" {
            return (alice, bob);
        }
        assert!(
            Instant::now() < until,
            "real invitation handshake must complete"
        );
        std::thread::sleep(Duration::from_millis(100));
    }
}

pub fn wait_rejected(
    creator: &mut Peer,
    contact: &mut Peer,
    id: &str,
    reason: &str,
    baseline: u64,
    members: u64,
) {
    let until = Instant::now() + Duration::from_secs(45);
    loop {
        poll(creator, id);
        let joining = poll(contact, id);
        let observed = evidence(creator, id, reason);
        assert_eq!(
            observed["members"], members,
            "rejected peer must not change persisted MLS membership"
        );
        assert_eq!(
            joining["state"], "pending",
            "rejected peer receives no Welcome"
        );
        if observed["rejections"].as_u64().unwrap() > baseline {
            return;
        }
        assert!(
            Instant::now() < until,
            "creator must process the real rejected admission packet"
        );
        std::thread::sleep(Duration::from_millis(100));
    }
}
