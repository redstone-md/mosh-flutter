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
        "dm_send" => serde_json::to_value(
            dm.send_message(arg, command["body"].as_str().unwrap().into())
                .unwrap(),
        )
        .unwrap(),
        _ => panic!("unknown DM command"),
    }
}

impl Peer {
    pub fn wait_dm_text(&mut self, session: &str, text: &str) -> Value {
        let until = Instant::now() + Duration::from_secs(30);
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
                "DM must deliver text, got {snapshot}"
            );
            std::thread::sleep(Duration::from_millis(100));
        }
    }
}
