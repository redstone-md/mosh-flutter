#[allow(dead_code, reason = "Shared independent-installation bridge harness.")]
mod link_support;

use link_support::{isolated_network_scenario, peer_process, Peer};
use serde_json::{json, Value};
use std::time::{Duration, Instant};

#[test]
#[ignore = "Requires an actual reachable signed public waiting carrier."]
fn actual_waiting_private_group_receives_text_and_offers_without_an_open_screen() {
    live_background("group");
}

#[test]
#[ignore = "Requires an actual reachable signed public waiting carrier."]
fn actual_waiting_public_channel_receives_text_and_offers_without_an_open_screen() {
    live_background("channel");
}

fn live_background(kind: &str) {
    let _network = isolated_network_scenario();
    let (mut sender, mut receiver, id) = connected(kind);
    receiver.ask(json!({"action":"background_set","interactive":false,"waiting":true}));
    let deadline = Instant::now() + Duration::from_secs(90);
    loop {
        let status = receiver.ask(json!({"action":"background_status"}));
        if status["actual_mode"] == "waiting" && status["reachability"] == "ready" {
            break;
        }
        assert!(
            Instant::now() < deadline,
            "waiting carrier not ready: {status}"
        );
        std::thread::sleep(Duration::from_millis(50));
    }
    sender
        .ask(json!({"action":"chat_send","kind":kind,"argument":id,"body":"New background text"}));
    let text = pending(&mut receiver, &mut sender, kind, &id);
    assert_eq!(text["text"], "New background text");
    assert_eq!(text["message_count"], 1);
    acknowledge(&mut receiver, &text);

    let sent = sender.ask(json!({"action":"attachment_send","kind":kind,"argument":id,
        "data":mosh_core::conversation::encode(include_bytes!("fixtures/preview.jpg")),
        "miniature":mosh_core::conversation::encode(include_bytes!("fixtures/miniature.jpg")),
        "preview":mosh_core::conversation::encode(include_bytes!("fixtures/preview.jpg"))}));
    assert!(sent["error"].is_null(), "attachment refused: {sent}");
    let offer = pending(&mut receiver, &mut sender, kind, &id);
    assert_ne!(offer["occurrence_id"], text["occurrence_id"]);
    acknowledge(&mut receiver, &offer);
    // First conversation observation since backgrounding: native services already
    // authenticated, persisted and notified both events without driving this poll.
    let snapshot = receiver.ask(json!({"action":"chat_poll","kind":kind,"argument":id}));
    assert!(snapshot["messages"]
        .as_array()
        .unwrap()
        .iter()
        .any(|message| message["body"] == "New background text"));
    let attachments = snapshot["attachments"].as_array().unwrap();
    assert_eq!(attachments.len(), 1);
    assert_eq!(attachments[0]["state"], "offered");
    assert_eq!(attachments[0]["completed_chunks"], 0);
    assert!(attachments[0]["local_path"].is_null());
    assert!(attachments[0]["preview_path"].is_null());
    assert_eq!(
        receiver.ask(json!({"action":"background_pending"})),
        json!([])
    );
}

fn connected(kind: &str) -> (Peer, Peer, String) {
    let (mut sender, mut receiver) = (Peer::new_api(), Peer::new_api());
    let id = if kind == "group" {
        let created = sender.ask(json!({"action":"chat_create","kind":kind}));
        receiver.ask(json!({"action":"chat_join","kind":kind,"argument":created["invite_uri"]}));
        created["group_id"].as_str().unwrap().to_owned()
    } else {
        let id = format!("background-{}", rand::random::<u64>());
        for peer in [&mut sender, &mut receiver] {
            peer.ask(json!({"action":"chat_join","kind":kind,"argument":id}));
        }
        id
    };
    let deadline = Instant::now() + Duration::from_secs(90);
    loop {
        let states: Vec<_> = [&mut sender, &mut receiver]
            .into_iter()
            .map(|peer| peer.ask(json!({"action":"chat_poll","kind":kind,"argument":id})))
            .collect();
        if states.iter().all(|state| {
            if kind == "group" {
                state["state"] == "ready" && state["member_count"].as_u64().unwrap_or(0) >= 2
            } else {
                state["mesh"]["peer_count"].as_u64().unwrap_or(0) > 0
            }
        }) {
            break;
        }
        assert!(Instant::now() < deadline, "setup failed: {states:?}");
        std::thread::sleep(Duration::from_millis(50));
    }
    sender.ask(json!({"action":"chat_send","kind":kind,"argument":id,"body":"Foreground positive control"}));
    let deadline = Instant::now() + Duration::from_secs(90);
    loop {
        sender.ask(json!({"action":"chat_poll","kind":kind,"argument":id}));
        let snapshot = receiver.ask(json!({"action":"chat_poll","kind":kind,"argument":id}));
        if snapshot["messages"].as_array().is_some_and(|rows| {
            rows.iter()
                .any(|row| row["body"] == "Foreground positive control")
        }) {
            break;
        }
        assert!(
            Instant::now() < deadline,
            "foreground positive control failed: {snapshot}"
        );
        std::thread::sleep(Duration::from_millis(50));
    }
    (sender, receiver, id)
}

fn pending(peer: &mut Peer, sender: &mut Peer, kind: &str, id: &str) -> Value {
    let deadline = Instant::now() + Duration::from_secs(90);
    loop {
        let entries = peer.ask(json!({"action":"background_pending"}));
        if let Some(entry) = entries
            .as_array()
            .unwrap()
            .iter()
            .find(|entry| entry["target"]["id"] == id)
        {
            return entry.clone();
        }
        // The ordinary sender still has a foreground chat. Only the receiving
        // installation must progress without conversation observations.
        sender.ask(json!({"action":"chat_poll","kind":kind,"argument":id}));
        if Instant::now() >= deadline {
            let snapshot = peer.ask(json!({"action":"chat_poll","kind":kind,"argument":id}));
            let execution = peer.ask(json!({"action":"background_status"}));
            panic!("native service did not notify {id}: {snapshot}; execution={execution}");
        }
        std::thread::sleep(Duration::from_millis(50));
    }
}

fn acknowledge(peer: &mut Peer, entry: &Value) {
    peer.ask(json!({"action":"background_ack","id":entry["id"],"revision":entry["revision"]}));
}

#[test]
#[ignore]
fn independent_installation_process() {
    peer_process();
}
