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
fn dm_wait_rejects_a_reply_after_its_deadline() {
    let _network = isolated_network_scenario();
    let mut peer = Peer::new_with_worker("peer_commands::slow_reply_peer_process");
    let failure = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        peer.wait_dm_text("late-reply", "Late text")
    }))
    .expect_err("a reply after the 30-second DM deadline must fail");
    let message = failure.downcast_ref::<String>().unwrap();
    assert!(
        message.contains("peer action \"dm_poll\" failed: timed out waiting on channel"),
        "{message}"
    );
}

#[test]
#[ignore = "Subprocess entry point"]
fn slow_reply_peer_process() {
    link_support::peer_process_with(|_, action, _| {
        if !matches!(action, "slow_reply" | "dm_poll") {
            return None;
        }
        // Cross the former 30-second command timeout with a real process.
        std::thread::sleep(Duration::from_secs(35));
        Some(match action {
            "dm_poll" => json!({"messages":[{"body":"Late text"}]}),
            _ => json!({"ready":true}),
        })
    });
}
