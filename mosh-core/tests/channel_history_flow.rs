#[allow(dead_code, reason = "Reuse independent-installation bridge harness.")]
mod link_support;

use link_support::{isolated_network_scenario, peer_process, Peer};
use serde_json::{json, Value};
use std::time::{Duration, Instant};

fn poll(peer: &mut Peer, id: &str) -> Value {
    peer.ask(json!({"action":"chat_poll", "kind":"channel", "argument":id}))
}

#[test]
fn a_channel_waits_for_an_available_history_holder() {
    let _network = isolated_network_scenario();
    let mut reader = Peer::new_api();
    let id = format!("history-wait-{}", rand::random::<u64>());
    reader.ask(json!({"action":"chat_join", "kind":"channel", "argument":id}));
    let snapshot = poll(&mut reader, &id);
    assert_eq!(snapshot["history_sync"]["state"], "waiting_for_source");
    assert!(snapshot["messages"].as_array().unwrap().is_empty());
}

#[test]
fn an_offline_author_is_recovered_from_an_available_holder_and_survives_restart() {
    let _network = isolated_network_scenario();
    let (mut author, mut holder) = (Peer::new_api(), Peer::new_api());
    let id = format!("history-copy-{}", rand::random::<u64>());
    for peer in [&mut author, &mut holder] {
        peer.ask(json!({"action":"chat_join", "kind":"channel", "argument":id}));
    }
    wait_for(&mut holder, &id, |s| {
        s["mesh"]["peer_count"].as_u64().unwrap_or(0) > 0
    });
    author.ask(
        json!({"action":"chat_send", "kind":"channel", "argument":id, "body":"Retained original"}),
    );
    let original = wait_for(&mut holder, &id, |s| {
        s["messages"].as_array().is_some_and(|m| !m.is_empty())
    });
    author.stop();
    // Discard volatile Moss gossip caches: only the holder's encrypted history remains.
    holder.restart();
    assert_eq!(
        poll(&mut holder, &id)["messages"][0]["body"],
        "Retained original"
    );
    let mut returning = Peer::new_api();
    returning.ask(json!({"action":"chat_join", "kind":"channel", "argument":id}));
    let deadline = Instant::now() + Duration::from_secs(15);
    let restored = loop {
        poll(&mut holder, &id);
        let snapshot = poll(&mut returning, &id);
        if snapshot["messages"][0]["body"] == "Retained original" {
            break snapshot;
        }
        assert!(
            Instant::now() < deadline,
            "history not recovered: {snapshot}"
        );
        std::thread::sleep(Duration::from_millis(50));
    };
    assert_eq!(
        restored["messages"][0]["metadata"]["origin"],
        original["messages"][0]["metadata"]["origin"]
    );
    returning.restart();
    let snapshot = poll(&mut returning, &id);
    assert_eq!(snapshot["messages"].as_array().unwrap().len(), 1);
    assert_eq!(snapshot["messages"][0]["body"], "Retained original");
}

fn wait_for(peer: &mut Peer, id: &str, ready: impl Fn(&Value) -> bool) -> Value {
    let deadline = Instant::now() + Duration::from_secs(15);
    loop {
        let snapshot = poll(peer, id);
        if ready(&snapshot) {
            return snapshot;
        }
        assert!(
            Instant::now() < deadline,
            "channel did not become ready: {snapshot}"
        );
        std::thread::sleep(Duration::from_millis(50));
    }
}

#[test]
fn recovered_attachment_offers_do_not_start_downloads() {
    let _network = isolated_network_scenario();
    let (mut author, mut holder) = (Peer::new_api(), Peer::new_api());
    let id = format!("history-file-{}", rand::random::<u64>());
    for peer in [&mut author, &mut holder] {
        peer.ask(json!({"action":"chat_join", "kind":"channel", "argument":id}));
    }
    wait_for(&mut holder, &id, |s| {
        s["mesh"]["peer_count"].as_u64().unwrap_or(0) > 0
    });
    let sent = author.ask(
        json!({"action":"attachment_send", "kind":"channel", "argument":id,
        "data":mosh_core::conversation::encode(include_bytes!("fixtures/preview.jpg")),
        "miniature":mosh_core::conversation::encode(include_bytes!("fixtures/miniature.jpg")),
        "preview":mosh_core::conversation::encode(include_bytes!("fixtures/preview.jpg"))}),
    );
    assert!(sent["error"].is_null(), "attachment send failed: {sent}");
    let original = wait_for(&mut holder, &id, |s| {
        !s["attachments"].as_array().unwrap().is_empty()
    });
    author.stop();
    holder.restart();
    let mut reader = Peer::new_api();
    reader.ask(json!({"action":"chat_join", "kind":"channel", "argument":id}));
    let deadline = Instant::now() + Duration::from_secs(15);
    let restored = loop {
        poll(&mut holder, &id);
        let snapshot = poll(&mut reader, &id);
        if !snapshot["attachments"].as_array().unwrap().is_empty() {
            break snapshot;
        }
        assert!(
            Instant::now() < deadline,
            "attachment history missing: {snapshot}"
        );
        std::thread::sleep(Duration::from_millis(50));
    };
    assert_eq!(
        restored["messages"][0]["metadata"]["origin"],
        original["messages"][0]["metadata"]["origin"]
    );
    assert_eq!(restored["attachments"][0]["state"], "offered");
    assert!(restored["attachments"][0]["local_path"].is_null());
    holder.stop();
    reader.restart();
    let snapshot = poll(&mut reader, &id);
    assert_eq!(snapshot["attachments"][0]["state"], "offered");
    assert!(snapshot["attachments"][0]["local_path"].is_null());
}

#[test]
fn a_large_history_uses_bounded_pages_without_losing_live_duplicates() {
    let _network = isolated_network_scenario();
    let mut holder = Peer::new_api();
    let id = format!("history-pages-{}", rand::random::<u64>());
    holder.ask(json!({"action":"chat_join", "kind":"channel", "argument":id}));
    for index in 0..20 {
        holder.ask(
            json!({"action":"chat_send", "kind":"channel", "argument":id,
            "body": format!("{index:02}{}", "x".repeat(4090))}),
        );
    }
    holder.restart();
    let mut reader = Peer::new_api();
    reader.ask(json!({"action":"chat_join", "kind":"channel", "argument":id}));
    let deadline = Instant::now() + Duration::from_secs(15);
    let restored = loop {
        poll(&mut holder, &id);
        let snapshot = poll(&mut reader, &id);
        if snapshot["messages"].as_array().unwrap().len() == 20 {
            break snapshot;
        }
        assert!(
            Instant::now() < deadline,
            "bounded pages stalled: {snapshot}"
        );
        std::thread::sleep(Duration::from_millis(30));
    };
    assert_eq!(restored["history_sync"]["state"], "complete");
    reader.restart();
    assert_eq!(
        poll(&mut reader, &id)["messages"].as_array().unwrap().len(),
        20
    );
}

#[test]
#[ignore = "Subprocess entry point"]
fn independent_installation_process() {
    peer_process();
}
