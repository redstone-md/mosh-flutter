#[allow(
    dead_code,
    reason = "Reuse the independent-installation bridge harness."
)]
mod link_support;

use link_support::{isolated_network_scenario, peer_process, Peer};
use serde_json::{json, Value};
use std::time::{Duration, Instant};

#[path = "private_group_history_flow/erasure.rs"]
mod erasure;
#[path = "private_group_history_flow/intervals.rs"]
mod intervals;
#[path = "private_group_history_flow/offer_facts.rs"]
mod offer_facts;
#[path = "private_group_history_flow/repair.rs"]
mod repair;

#[test]
fn an_offline_group_author_is_recovered_from_an_ordinary_holder_after_restart() {
    recover(false);
}

#[test]
#[ignore = "Needs a network with an actual signed reachable relay, not loopback NAT fiction."]
fn actual_waiting_carrier_recovers_group_history_without_ui_polling_or_duplicate_notification() {
    recover(true);
}

#[test]
fn attachment_recovery_keeps_original_offers_without_downloading_files() {
    recover_attachment(false);
}

#[test]
fn an_imported_attachment_remains_recoverable_from_its_restarted_holder() {
    recover_attachment(true);
}

fn recover_attachment(imported_holder: bool) {
    let _network = isolated_network_scenario();
    let (mut author, mut holder, mut returning, id) = three_members();
    returning.stop();
    if imported_holder {
        holder.stop();
    }
    offer_facts::send_image(&mut author, &id);
    if imported_holder {
        // No live manifest remains in the publisher's room cache after restart.
        author.restart();
        holder.restart();
    }
    let original = wait_text(&mut [&mut author, &mut holder], &id);
    if imported_holder {
        assert!(original["attachments"][0]["preview_path"].is_null());
    }
    offer_facts::assert_original_offer(&mut holder, &id, imported_holder);
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
    assert!(recovered["attachments"][0]["preview_path"].is_null());
    assert_eq!(recovered["history_sync"]["state"], "complete");
    offer_facts::assert_original_offer(&mut returning, &id, true);
}

fn recover(background: bool) {
    let _network = isolated_network_scenario();
    let (mut author, mut holder, mut returning, id) = three_members();
    let mut carrier = background.then(Peer::new_api);
    if let Some(peer) = &mut carrier {
        peer.ask(json!({"action":"background_set","interactive":true,"waiting":true}));
    }
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
            panic!("Actual Waiting acceptance requires the current native ABI");
        }
        wait_carrier(&mut holder);
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
            wait_carrier(peer);
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
    let deadline = Instant::now() + Duration::from_secs(90);
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
    for peer in [&mut author, &mut holder, &mut returning] {
        peer.ask(json!({"action":"background_set","interactive":true,"waiting":true}));
    }
    let created = author.ask(json!({"action":"chat_create", "kind":"group"}));
    let id = created["group_id"].as_str().unwrap().to_owned();
    for peer in [&mut holder, &mut returning] {
        peer.ask(json!({"action":"chat_join", "kind":"group", "argument":created["invite_uri"]}));
    }
    let deadline = Instant::now() + Duration::from_secs(90);
    loop {
        let counts = [&mut author, &mut holder, &mut returning]
            .into_iter()
            .map(|peer| poll(peer, &id)["member_count"].as_u64().unwrap_or(0))
            .collect::<Vec<_>>();
        if counts.iter().all(|count| *count == 3) {
            break;
        }
        assert!(
            Instant::now() < deadline,
            "three group members did not converge: {counts:?}"
        );
        std::thread::sleep(Duration::from_millis(50));
    }
    (author, holder, returning, id)
}

fn poll(peer: &mut Peer, id: &str) -> Value {
    peer.ask(json!({"action":"chat_poll", "kind":"group", "argument":id}))
}

fn wait_notification(peer: &mut Peer, id: &str) -> Value {
    let deadline = Instant::now() + Duration::from_secs(90);
    loop {
        let last = peer.ask(json!({"action":"background_pending"}));
        if let Some(notification) = last
            .as_array()
            .and_then(|rows| rows.iter().find(|row| row["target"]["id"] == id))
        {
            return notification.clone();
        }
        if Instant::now() >= deadline {
            let status = peer.ask(json!({"action":"background_status"}));
            let saved = poll(peer, id);
            panic!("group did not notify without UI polling: {last}; native status={status}; post-timeout snapshot={saved}");
        }
        std::thread::sleep(Duration::from_millis(50));
    }
}

#[test]
#[ignore = "Subprocess entry point"]
fn independent_installation_process() {
    peer_process();
}

fn wait_carrier(peer: &mut Peer) {
    let deadline = Instant::now() + Duration::from_secs(90);
    loop {
        let state = peer.ask(json!({"action":"background_status"}));
        if state["actual_mode"] == "waiting" && state["reachability"] == "ready" {
            assert_eq!(state["attachment_count"], 1);
            return;
        }
        assert!(
            Instant::now() < deadline,
            "actual Waiting carrier is unavailable: {state}"
        );
        std::thread::sleep(Duration::from_millis(100));
    }
}
