use super::*;

#[test]
fn commands_wait_for_a_slow_live_peer() {
    let _network = isolated_network_scenario();
    let mut peer = Peer::new_with_worker("peer_commands::slow_reply_peer_process");
    assert_eq!(
        peer.ask(json!({"action":"slow_reply"})),
        json!({"ready":true})
    );
}

#[test]
#[ignore = "Subprocess entry point"]
fn slow_reply_peer_process() {
    link_support::peer_process_with(|_, action, _| {
        if action != "slow_reply" {
            return None;
        }
        // Cross the former 30-second command timeout with a real process.
        std::thread::sleep(Duration::from_secs(35));
        Some(json!({"ready":true}))
    });
}
