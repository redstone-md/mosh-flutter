#[allow(
    dead_code,
    reason = "Shared harness also serves other integration suites."
)]
mod link_support;

use link_support::{isolated_network_scenario, peer_process, Peer};
use serde_json::json;
use std::time::{Duration, Instant};

fn wait_state(peer: &mut Peer, session: &str, state: &str) {
    let deadline = Instant::now() + Duration::from_secs(45);
    loop {
        let snapshot = peer.ask(json!({"action":"dm_poll","argument":session}));
        if snapshot["state"] == state {
            return;
        }
        assert!(
            Instant::now() < deadline,
            "DM did not reach {state}: {snapshot}"
        );
        std::thread::sleep(Duration::from_millis(100));
    }
}

#[test]
fn offline_identity_advertisements_follow_bounded_presence_retries() {
    let _network = isolated_network_scenario();
    let mut alice = Peer::new_recorded_api();
    let mut bob = Peer::new_api();
    let invite = alice.ask(json!({"action":"dm_invite"}));
    let session = invite["session_id"].as_str().unwrap();
    bob.ask(json!({"action":"dm_accept","argument":invite["invite_uri"]}));
    wait_state(&mut alice, session, "connected");
    wait_state(&mut bob, session, "connected");
    bob.stop();
    wait_state(&mut alice, session, "handshaking");
    let before = alice.publication_count();
    let until = Instant::now() + Duration::from_secs(30);
    while Instant::now() < until {
        alice.ask(json!({"action":"dm_poll","argument":session}));
        std::thread::sleep(Duration::from_millis(200));
    }
    let publications = alice.publication_count() - before;
    eprintln!("Offline DM publications in 30 seconds: {publications}");
    assert!(publications > 0, "offline contact must retain retry probes");
    assert!(
        publications <= 12,
        "offline DM published {publications} times in 30 seconds"
    );
    bob.restart();
    alice.ask(json!({"action":"dm_send","argument":session,"body":"after idle"}));
    bob.wait_dm_text(session, "after idle");
    wait_state(&mut alice, session, "connected");
    wait_state(&mut bob, session, "connected");
}

#[test]
#[ignore]
fn independent_installation_process() {
    peer_process();
}
