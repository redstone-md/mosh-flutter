#[allow(dead_code, reason = "Shared independent-installation harness.")]
mod link_support;

use link_support::{isolated_network_scenario, peer_process, Peer};
use serde_json::{json, Value};
use std::time::{Duration, Instant};

fn wait(peer: &mut Peer, request: Value, ready: impl Fn(&Value) -> bool) -> Value {
    let deadline = Instant::now() + Duration::from_secs(90);
    loop {
        let value = peer.ask(request.clone());
        if ready(&value) {
            return value;
        }
        assert!(Instant::now() < deadline, "background observation: {value}");
        std::thread::sleep(Duration::from_millis(100));
    }
}

#[test]
fn retained_background_dm_is_durable_without_ui_polling_or_a_read_receipt() {
    background_receipt(false);
}

#[test]
#[ignore = "Needs a network with an actual signed reachable relay; not loopback NAT fiction."]
fn actual_waiting_carrier_retains_background_dm() {
    background_receipt(true);
}

fn background_receipt(require_carrier: bool) {
    let _network = isolated_network_scenario();
    let mut sender = Peer::new_api();
    let mut recipient = Peer::new_api();
    let _carrier = Peer::new_api();
    let invite = sender.ask(json!({"action":"dm_invite"}));
    let id = invite["session_id"].as_str().unwrap();
    recipient.ask(json!({"action":"dm_accept","argument":invite["invite_uri"]}));
    for peer in [&mut sender, &mut recipient] {
        wait(peer, json!({"action":"dm_poll","argument":id}), |s| {
            s["state"] == "connected"
        });
        peer.ask(json!({"action":"background_set","interactive":true,"waiting":true}));
        peer.ask(json!({"action":"dm_receipts","enabled":true}));
    }
    let transition =
        recipient.ask(json!({"action":"background_set","interactive":false,"waiting":true}));
    if transition["actual_mode"] == "unsupported" && !require_carrier {
        assert_eq!(transition["attachment_count"], 0);
        assert_eq!(transition["reachability"], "unavailable");
        eprintln!("Old optional ABI: unsupported/offline verified; candidate receipt needs waiting library");
        return;
    }
    if require_carrier {
        let state = wait(&mut recipient, json!({"action":"background_status"}), |s| {
            s["actual_mode"] == "waiting" && s["reachability"] == "ready"
        });
        assert_eq!(state["attachment_count"], 1);
        eprintln!("Actual candidate carrier ready: {state}");
    } else {
        let state = recipient.ask(json!({"action":"background_status"}));
        assert_eq!(state["requested_mode"], "waiting");
        if state["actual_mode"] == "active" {
            assert_ne!(
                state["reachability"], "ready",
                "a missing carrier is not success"
            );
        }
    }
    sender.ask(json!({"action":"dm_send","argument":id,"body":"private background text"}));
    // Reading the durable queue does not poll/list a conversation or drive its pump.
    let pending = wait(
        &mut recipient,
        json!({"action":"background_pending"}),
        |s| s.as_array().is_some_and(|entries| !entries.is_empty()),
    );
    assert_eq!(pending.as_array().unwrap().len(), 1);
    assert_eq!(pending[0]["target"]["id"], id);
    assert_eq!(pending[0]["text"], "private background text");
    recipient.ask(
        json!({"action":"background_ack","id":pending[0]["id"],"revision":pending[0]["revision"]}),
    );
    assert_eq!(
        recipient.ask(json!({"action":"background_pending"})),
        json!([])
    );
    let sent = wait(
        &mut sender,
        json!({"action":"dm_poll","argument":id}),
        |s| {
            s["messages"].as_array().is_some_and(|rows| {
                rows.iter().any(|m| {
                    m["body"] == "private background text" && m["delivery_status"] == "delivered"
                })
            })
        },
    );
    assert!(sent["messages"]
        .as_array()
        .unwrap()
        .iter()
        .all(|m| m["read"] != true));
    // A foreground reply uses the same retained authenticated conversation.
    recipient.ask(json!({"action":"background_set","interactive":true,"waiting":true}));
    recipient.ask(json!({"action":"dm_send","argument":id,"body":"retained foreground reply"}));
    sender.wait_dm_text(id, "retained foreground reply");
    recipient.ask(json!({"action":"background_set","interactive":false,"waiting":true}));
    recipient.restart();
    assert_eq!(
        recipient.ask(json!({"action":"background_pending"})),
        json!([])
    );
    recipient.wait_dm_text(id, "private background text");
}

#[test]
fn stop_releases_network_while_retaining_the_conversation_and_saved_off_intent() {
    let _network = isolated_network_scenario();
    let mut sender = Peer::new_api();
    let mut recipient = Peer::new_api();
    let invite = sender.ask(json!({"action":"dm_invite"}));
    let id = invite["session_id"].as_str().unwrap();
    recipient.ask(json!({"action":"dm_accept","argument":invite["invite_uri"]}));
    let before = wait(
        &mut recipient,
        json!({"action":"dm_poll","argument":id}),
        |s| s["state"] == "connected",
    );
    let port = before["mesh"]["listen_port"].as_u64().unwrap() as u16;
    recipient.ask(json!({"action":"background_set","interactive":true,"waiting":true}));
    let stopped =
        recipient.ask(json!({"action":"background_set","interactive":false,"waiting":false}));
    assert_eq!(stopped["actual_mode"], "offline");
    let tcp = std::net::TcpListener::bind(("0.0.0.0", port))
        .expect("native TCP listener must be released");
    let udp =
        std::net::UdpSocket::bind(("0.0.0.0", port)).expect("native UDP listener must be released");
    drop((tcp, udp));
    recipient.ask(json!({"action":"background_set","interactive":true,"waiting":false}));
    sender.ask(json!({"action":"dm_send","argument":id,"body":"after retained resume"}));
    recipient.wait_dm_text(id, "after retained resume");
    let after = recipient.ask(json!({"action":"dm_poll","argument":id}));
    assert_eq!(before["mesh"]["public_key"], after["mesh"]["public_key"]);
    recipient.ask(json!({"action":"background_set","interactive":false,"waiting":false}));
    recipient.restart();
    let off = recipient.ask(json!({"action":"background_status"}));
    assert_eq!(off["waiting_enabled"], false);
    assert_eq!(off["actual_mode"], "offline");
    recipient.ask(json!({"action":"background_set","interactive":true,"waiting":false}));
    recipient.wait_dm_text(id, "after retained resume");
}

#[test]
fn stop_waits_for_admitted_call_then_releases_the_transport() {
    let _network = isolated_network_scenario();
    let mut caller = Peer::new_api();
    let mut callee = Peer::new_api();
    let invite = caller.ask(json!({"action":"dm_invite"}));
    let id = invite["session_id"].as_str().unwrap();
    callee.ask(json!({"action":"dm_accept","argument":invite["invite_uri"]}));
    for peer in [&mut caller, &mut callee] {
        wait(peer, json!({"action":"dm_poll","argument":id}), |s| {
            s["state"] == "connected"
        });
        peer.ask(json!({"action":"background_set","interactive":true,"waiting":true}));
    }
    let started = caller.ask(json!({"action":"call_start","argument":id}));
    assert!(started.get("error").is_none(), "{started}");
    let call = started["call_id"].as_str().unwrap();
    let stopped =
        caller.ask(json!({"action":"background_set","interactive":false,"waiting":false}));
    assert_eq!(stopped["waiting_enabled"], false);
    assert_eq!(stopped["current_calls"], 1);
    assert_eq!(stopped["actual_mode"], "active");
    caller.ask(json!({"action":"call_end","argument":id,"call_id":call}));
    let off = wait(&mut caller, json!({"action":"background_status"}), |s| {
        s["actual_mode"] == "offline"
    });
    assert_eq!(off["current_calls"], 0);
    assert_eq!(off["waiting_enabled"], false);
}

#[test]
#[ignore]
fn independent_installation_process() {
    peer_process();
}
