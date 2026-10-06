#[allow(
    dead_code,
    reason = "Shared independent-process harness includes device-link scenarios."
)]
mod link_support;

use link_support::{isolated_network_scenario, peer_process, Peer};
use mosh_core::conversation::encode;
use serde_json::{json, Value};
use std::time::{Duration, Instant};

const PREVIEW: &[u8] = include_bytes!("fixtures/preview.jpg");
const MINIATURE: &[u8] = include_bytes!("fixtures/miniature.jpg");

fn poll(peer: &mut Peer, kind: &str, id: &str) -> Value {
    peer.ask(json!({"action":"chat_poll", "kind":kind, "argument":id}))
}

fn wait_ready(sender: &mut Peer, receiver: &mut Peer, kind: &str, id: &str) {
    let until = Instant::now() + Duration::from_secs(45);
    loop {
        let a = poll(sender, kind, id);
        let b = poll(receiver, kind, id);
        let ready = match kind {
            "dm" => a["state"] == "connected" && b["state"] == "connected",
            "group" => a["member_count"] == 2 && b["member_count"] == 2,
            _ => {
                a["mesh"]["peer_count"].as_u64().unwrap_or(0) > 0
                    && b["mesh"]["peer_count"].as_u64().unwrap_or(0) > 0
            }
        };
        if ready {
            return;
        }
        assert!(Instant::now() < until, "peers must join: {a} / {b}");
        std::thread::sleep(Duration::from_millis(100));
    }
}

fn wait_preview(sender: &mut Peer, receiver: &mut Peer, kind: &str, id: &str) -> Value {
    let until = Instant::now() + Duration::from_secs(45);
    loop {
        poll(sender, kind, id);
        let snapshot = poll(receiver, kind, id);
        if snapshot["attachments"][0]["preview_path"].is_string() {
            return snapshot;
        }
        assert!(Instant::now() < until, "preview must arrive: {snapshot}");
        std::thread::sleep(Duration::from_millis(100));
    }
}

fn exercise(kind: &str) {
    let _network = isolated_network_scenario();
    let mut sender = Peer::new_api();
    let mut receiver = Peer::new_api();
    let id = open_chat(&mut sender, &mut receiver, kind);
    wait_ready(&mut sender, &mut receiver, kind, &id);
    let accepted = sender.ask(
        json!({"action":"attachment_send", "kind":kind, "argument":id,
        "data":encode(PREVIEW), "miniature":encode(MINIATURE), "preview":encode(PREVIEW)}),
    );
    assert!(accepted.get("error").is_none(), "{accepted}");
    let snapshot = wait_preview(&mut sender, &mut receiver, kind, &id);
    assert_preview(&snapshot);
    sender.stop();
    receiver.restart();
    let restored = poll(&mut receiver, kind, &id);
    assert_preview(&restored);
    let path = restored["attachments"][0]["preview_path"].as_str().unwrap();
    let deleted = receiver.ask(
        json!({"action":"attachment_delete", "kind":kind, "argument":id,
        "message_id":restored["messages"][0]["message_id"]}),
    );
    assert!(deleted.get("error").is_none(), "{deleted}");
    assert!(poll(&mut receiver, kind, &id)["attachments"]
        .as_array()
        .unwrap()
        .is_empty());
    assert!(
        !std::path::Path::new(path).exists(),
        "parent deletion removes its preview"
    );
    receiver.restart();
    assert!(poll(&mut receiver, kind, &id)["attachments"]
        .as_array()
        .unwrap()
        .is_empty());
}

fn assert_preview(snapshot: &Value) {
    assert_eq!(snapshot["messages"].as_array().unwrap().len(), 1);
    assert_eq!(snapshot["attachments"].as_array().unwrap().len(), 1);
    assert_eq!(snapshot["attachments"][0]["state"], "offered");
    assert!(snapshot["attachments"][0]["local_path"].is_null());
    assert_eq!(
        snapshot["messages"][0]["attachment"]["thumbnail_b64"],
        encode(MINIATURE)
    );
    let path = snapshot["attachments"][0]["preview_path"].as_str().unwrap();
    assert_eq!(std::fs::read(path).unwrap(), PREVIEW);
}

fn open_chat(sender: &mut Peer, receiver: &mut Peer, kind: &str) -> String {
    let invite = match kind {
        "dm" => sender.ask(json!({"action":"dm_invite"})),
        "group" => sender.ask(json!({"action":"chat_create"})),
        _ => {
            let id = format!("preview-{}", rand::random::<u64>());
            for peer in [sender, receiver] {
                peer.ask(json!({"action":"chat_join", "kind":kind, "argument":id}));
            }
            return id;
        }
    };
    let action = if kind == "dm" {
        "dm_accept"
    } else {
        "chat_join"
    };
    receiver.ask(json!({"action":action, "kind":kind, "argument":invite["invite_uri"]}));
    invite[if kind == "dm" {
        "session_id"
    } else {
        "group_id"
    }]
    .as_str()
    .unwrap()
    .into()
}

#[test]
fn dm_preview_survives_restart_and_is_erased_with_its_message() {
    exercise("dm");
}

#[test]
fn group_preview_survives_restart_and_is_erased_with_its_message() {
    exercise("group");
}

#[test]
fn channel_preview_survives_restart_and_is_erased_with_its_message() {
    exercise("channel");
}

#[test]
#[ignore]
fn independent_installation_process() {
    peer_process();
}
