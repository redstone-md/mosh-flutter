use super::Peer;
use mosh_core::private_dm_runtime::{AcceptInviteRequest, PrivateDmRuntime, StartSessionRequest};
use serde_json::{json, Value};
use std::time::{Duration, Instant};

pub fn command(dm: &mut PrivateDmRuntime, action: &str, arg: &str, command: &Value) -> Value {
    match action {
        "dm_invite" => serde_json::to_value(
            dm.create_invite(StartSessionRequest {
                display_name: "Original desktop".into(),
                listen_port: 0,
                static_peer: None,
            })
            .unwrap(),
        )
        .unwrap(),
        "dm_accept" => serde_json::to_value(
            dm.accept_invite(AcceptInviteRequest {
                invite_uri: arg.into(),
                display_name: "Counterpart".into(),
                listen_port: 0,
                static_peer: None,
            })
            .unwrap(),
        )
        .unwrap(),
        "dm_poll" => serde_json::to_value(dm.poll_session(arg).unwrap()).unwrap(),
        "dm_list" => serde_json::to_value(dm.list_sessions().unwrap()).unwrap(),
        "dm_send" => serde_json::to_value(
            dm.send_message(arg, command["body"].as_str().unwrap().into())
                .unwrap(),
        )
        .unwrap(),
        "dm_try_send" => match dm.send_message(arg, command["body"].as_str().unwrap().into()) {
            Ok(snapshot) => serde_json::to_value(snapshot).unwrap(),
            Err(error) => json!({"error":error.to_string()}),
        },
        "dm_typing" => {
            dm.typing_signal(arg).unwrap();
            json!({})
        }
        "dm_receipts" => {
            dm.set_read_receipts_enabled(command["enabled"].as_bool().unwrap())
                .unwrap();
            json!({})
        }
        "dm_viewed" => {
            dm.mark_viewed(arg).unwrap();
            json!({})
        }
        _ => panic!("unknown DM command"),
    }
}

/// Budget for text that travels live between connected devices.
const LIVE_WAIT: Duration = Duration::from_secs(30);

/// Budget for text a returning device can only get through recovery import
/// (ADR 0032). Recovery is paced by protocol timers, not by the network: 10 s
/// on the saved source before switching (SOURCE_TIMEOUT_MS), then a 5 s probe
/// (PROBE_MS), and every lost request or batch costs another retry interval
/// of up to 5 s. A clean run takes ~14 s; 60 s leaves room for ~9 lost
/// packets, where the live budget failed CI once ~3 were lost.
const RECOVERY_WAIT: Duration = Duration::from_secs(60);

impl Peer {
    pub fn wait_dm_text(&mut self, session: &str, text: &str) -> Value {
        self.wait_dm_text_within(session, text, LIVE_WAIT)
    }

    /// Waits for text a returning device can only get through recovery.
    #[allow(dead_code)] // Only the DM recovery tests use it; also compiles into device_link_flow.
    pub fn wait_recovered_dm_text(&mut self, session: &str, text: &str) -> Value {
        self.wait_dm_text_within(session, text, RECOVERY_WAIT)
    }

    fn wait_dm_text_within(&mut self, session: &str, text: &str, budget: Duration) -> Value {
        let until = Instant::now() + budget;
        loop {
            let snapshot = self.ask(json!({"action":"dm_poll","argument":session}));
            if snapshot["messages"]
                .as_array()
                .unwrap()
                .iter()
                .any(|m| m["body"] == text)
            {
                return snapshot;
            }
            assert!(
                Instant::now() < until,
                "DM must deliver {text}, got {snapshot}"
            );
            std::thread::sleep(Duration::from_millis(100));
        }
    }
}
