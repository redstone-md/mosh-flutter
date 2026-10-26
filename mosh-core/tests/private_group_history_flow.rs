#[allow(
    dead_code,
    reason = "Reuse the independent-installation bridge harness."
)]
mod link_support;

use link_support::{isolated_network_scenario, peer_process, Peer};
use serde_json::{json, Value};
use std::time::{Duration, Instant};

#[test]
fn an_offline_group_author_is_recovered_from_an_ordinary_holder_after_restart() {
    recover(false);
}

#[test]
fn native_background_group_receipt_and_recovery_need_no_ui_poll_or_duplicate_notification() {
    recover(true);
}

#[test]
fn attachment_recovery_keeps_original_offers_without_downloading_files() {
    let _network = isolated_network_scenario();
    let (mut author, mut holder, mut returning, id) = three_members();
    returning.stop();
    assert_eq!(
        author.ask(
            json!({"action":"attachment_send", "kind":"group", "argument":id,
        "data":mosh_core::conversation::encode(include_bytes!("fixtures/preview.jpg")),
        "miniature":mosh_core::conversation::encode(include_bytes!("fixtures/miniature.jpg")),
        "preview":mosh_core::conversation::encode(include_bytes!("fixtures/preview.jpg"))})
        ),
        json!({})
    );
    let original = wait_text(&mut [&mut author, &mut holder], &id);
    author.stop();
    holder.restart();
    returning.restart();
    let recovered = wait_text(&mut [&mut holder, &mut returning], &id);
    assert_eq!(
        recovered["messages"][0]["metadata"]["origin"],
        original["messages"][0]["metadata"]["origin"]
    );
    assert_eq!(
        recovered["messages"][0]["attachment"],
        original["messages"][0]["attachment"]
    );
    assert_eq!(recovered["attachments"][0]["state"], "offered");
    assert!(recovered["attachments"][0]["local_path"].is_null());
    assert_eq!(recovered["history_sync"]["state"], "complete");
}

fn recover(background: bool) {
    let _network = isolated_network_scenario();
    let (mut author, mut holder, mut returning, id) = three_members();
    for peer in [&mut author, &mut holder, &mut returning] {
        peer.ask(json!({"action":"background_set","interactive":true,"waiting":true}));
    }
    returning.stop();
    if background {
        let state =
            holder.ask(json!({"action":"background_set","interactive":false,"waiting":true}));
        if state["actual_mode"] == "unsupported" {
            assert_eq!(state["reachability"], "unavailable");
            eprintln!("Old optional ABI honestly suspends: native background requires the waiting library");
            return;
        }
    }
    author.ask(json!({"action":"chat_send", "kind":"group", "argument":id, "body":"Original author can be offline"}));
    let original = if background {
        assert_eq!(
            wait_notification(&mut holder, &id)["text"],
            "Original author can be offline"
        );
        poll(&mut holder, &id)
    } else {
        wait_text(&mut [&mut author, &mut holder], &id)
    };
    author.stop();
    holder.restart();
    returning.restart();
    let (recovered, notification) = if background {
        for peer in [&mut holder, &mut returning] {
            peer.ask(json!({"action":"background_set","interactive":false,"waiting":true}));
        }
        let notification = wait_notification(&mut returning, &id);
        assert_eq!(notification["text"], "Original author can be offline");
        assert_eq!(notification["message_count"], 1);
        (poll(&mut returning, &id), Some(notification))
    } else {
        (wait_text(&mut [&mut holder, &mut returning], &id), None)
    };
    assert_eq!(
        recovered["messages"][0]["metadata"]["origin"],
        original["messages"][0]["metadata"]["origin"]
    );
    assert_eq!(recovered["history_sync"]["state"], "complete");
    if let Some(notification) = notification {
        returning.ask(json!({"action":"background_ack","id":notification["id"],"revision":notification["revision"]}));
    }
    returning.restart();
    assert_eq!(
        returning.ask(json!({"action":"background_pending"})),
        json!([])
    );
    let saved = poll(&mut returning, &id);
    assert_eq!(saved["messages"].as_array().unwrap().len(), 1);
    assert_eq!(
        saved["messages"][0]["body"],
        "Original author can be offline"
    );
}

fn wait_text(peers: &mut [&mut Peer], id: &str) -> Value {
    let deadline = Instant::now() + Duration::from_secs(20);
    loop {
        let last = peers.iter_mut().map(|peer| poll(peer, id)).last().unwrap();
        if last["messages"]
            .as_array()
            .is_some_and(|rows| !rows.is_empty())
        {
            return last;
        }
        assert!(
            Instant::now() < deadline,
            "ordinary holder did not recover group text: {last}"
        );
        std::thread::sleep(Duration::from_millis(50));
    }
}

fn three_members() -> (Peer, Peer, Peer, String) {
    let (mut author, mut holder, mut returning) =
        (Peer::new_api(), Peer::new_api(), Peer::new_api());
    let created = author.ask(json!({"action":"chat_create", "kind":"group"}));
    let id = created["group_id"].as_str().unwrap().to_owned();
    for peer in [&mut holder, &mut returning] {
        peer.ask(json!({"action":"chat_join", "kind":"group", "argument":created["invite_uri"]}));
    }
    let deadline = Instant::now() + Duration::from_secs(20);
    loop {
        let complete = [&mut author, &mut holder, &mut returning]
            .into_iter()
            .map(|peer| poll(peer, &id)["member_count"].as_u64().unwrap_or(0))
            .all(|count| count == 3);
        if complete {
            break;
        }
        assert!(
            Instant::now() < deadline,
            "three group members did not converge"
        );
        std::thread::sleep(Duration::from_millis(50));
    }
    (author, holder, returning, id)
}

fn poll(peer: &mut Peer, id: &str) -> Value {
    peer.ask(json!({"action":"chat_poll", "kind":"group", "argument":id}))
}

fn wait_notification(peer: &mut Peer, id: &str) -> Value {
    let deadline = Instant::now() + Duration::from_secs(20);
    loop {
        let last = peer.ask(json!({"action":"background_pending"}));
        if let Some(notification) = last
            .as_array()
            .and_then(|rows| rows.iter().find(|row| row["target"]["id"] == id))
        {
            return notification.clone();
        }
        assert!(
            Instant::now() < deadline,
            "group did not durably notify without UI polling: {last}"
        );
        std::thread::sleep(Duration::from_millis(50));
    }
}

#[test]
#[ignore = "Subprocess entry point"]
fn independent_installation_process() {
    peer_process();
}
