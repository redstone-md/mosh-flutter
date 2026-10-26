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
        peer.ask(json!({"action":"dm_receipts","enabled":true}));
    }
    if require_carrier {
        sender.assert_bidirectional_dm_route(&mut recipient, id);
    }
    // The sender represents desktop Mosh: no Android execution API is attached.
    recipient.ask(json!({"action":"background_set","interactive":true,"waiting":true}));
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
    if require_carrier {
        background_attachment_policy(&mut sender, &mut recipient, id);
    }
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

fn background_attachment_policy(sender: &mut Peer, receiver: &mut Peer, id: &str) {
    let sent = sender.ask(json!({"action":"attachment_send","kind":"dm","argument":id,
        "data":mosh_core::conversation::encode(include_bytes!("fixtures/preview.jpg")),
        "miniature":mosh_core::conversation::encode(include_bytes!("fixtures/miniature.jpg")),
        "preview":mosh_core::conversation::encode(include_bytes!("fixtures/preview.jpg"))}));
    assert!(
        sent["error"].is_null(),
        "attachment admission refused: {sent}"
    );
    let pending = wait(receiver, json!({"action":"background_pending"}), |s| {
        s.as_array().is_some_and(|entries| !entries.is_empty())
    });
    let snapshot = receiver.ask(json!({"action":"dm_poll","argument":id}));
    let attachment = &snapshot["attachments"][0];
    assert_eq!(attachment["state"], "offered");
    assert_eq!(attachment["completed_chunks"], 0);
    assert!(attachment["local_path"].is_null());
    assert!(attachment["preview_path"].is_null());
    receiver.ask(
        json!({"action":"background_ack","id":pending[0]["id"],"revision":pending[0]["revision"]}),
    );
    receiver.ask(json!({"action":"background_set","interactive":false,"waiting":false}));
    let range = receiver.ask(
        json!({"action":"attachment_range","kind":"dm","argument":id,
        "attachment_id":attachment["attachment_id"]}),
    );
    assert_eq!(
        range["state"], "Unknown",
        "a stale media HTTP request must not admit background work"
    );
    let state = receiver.ask(json!({"action":"background_status"}));
    assert_eq!(state["actual_mode"], "offline");
    assert_eq!(state["current_user_transfers"], 0);
    receiver.ask(json!({"action":"background_set","interactive":true,"waiting":true}));
    let admitted = receiver.ask(
        json!({"action":"attachment_user_download", "kind":"dm", "argument":id,
        "attachment_id":attachment["attachment_id"]}),
    );
    assert!(
        admitted["error"].is_null(),
        "explicit native download refused: {admitted}"
    );
    let completed = wait(
        receiver,
        json!({"action":"dm_poll","argument":id}),
        |snapshot| {
            snapshot["attachments"].as_array().is_some_and(|rows| {
                rows.iter().any(|row| {
                    row["attachment_id"] == attachment["attachment_id"]
                        && row["state"] == "available"
                })
            })
        },
    );
    let received = &completed["attachments"][0];
    assert_eq!(received["completed_chunks"], received["chunk_count"]);
    let status = receiver.ask(json!({"action":"background_status"}));
    let records = status["user_transfers"].as_array().unwrap();
    let transfer = records
        .iter()
        .find(|record| record["id"] == admitted["transfer_id"])
        .unwrap();
    assert_eq!(transfer["state"], "complete");
    assert_eq!(transfer["completed_bytes"], transfer["total_bytes"]);
    receiver.ask(json!({"action":"background_set","interactive":false,"waiting":true}));
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
fn authenticated_background_call_buttons_expire_and_do_not_accept_media() {
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
    let stale = callee.ask(json!({"action":"background_call_action", "capability":"0".repeat(64)}));
    assert_eq!(stale["outcome"], "stale");
    let started = caller.ask(json!({"action":"call_start","argument":id}));
    let call = started["call_id"].as_str().unwrap();
    let entry = call_entry(&mut callee, call, "incoming");
    let answer = entry["call"]["answer_capability"].as_str().unwrap();
    assert_eq!(answer.len(), 64);
    let applied = callee.ask(json!({"action":"background_call_action", "capability":answer}));
    assert_eq!(applied["outcome"], "applied");
    assert_eq!(applied["action"], "answer");
    assert_eq!(applied["target"]["id"], id);
    let current = callee.ask(json!({"action":"dm_poll", "argument":id}));
    assert_eq!(
        current["pending_call"]["answer_pending"], false,
        "answer intent alone must not accept or capture"
    );
    let replay = callee.ask(json!({"action":"background_call_action", "capability":answer}));
    assert_eq!(replay["outcome"], "stale");
    let renewed = call_entry(&mut callee, call, "incoming");
    assert_eq!(renewed["id"], entry["id"]);
    assert_ne!(renewed["call"]["answer_capability"], answer);
    assert!(renewed["revision"].as_u64() > entry["revision"].as_u64());
    caller.ask(json!({"action":"call_end","argument":id,"call_id":call}));
    let ended = wait(&mut callee, json!({"action":"background_pending"}), |s| {
        s.as_array()
            .is_some_and(|items| items.iter().any(|item| item["call"]["phase"] == "ended"))
    });
    let ended = ended
        .as_array()
        .unwrap()
        .iter()
        .find(|entry| entry["call"]["phase"] == "ended")
        .unwrap();
    assert_eq!(entry["id"], ended["id"]);
    assert!(ended["revision"].as_u64() > entry["revision"].as_u64());
    let decline = entry["call"]["decline_capability"].as_str().unwrap();
    let stale = callee.ask(json!({"action":"background_call_action", "capability":decline}));
    assert_eq!(stale["outcome"], "stale");
}

fn call_entry(peer: &mut Peer, call: &str, phase: &str) -> Value {
    let pending = wait(peer, json!({"action":"background_pending"}), |s| {
        s.as_array().is_some_and(|items| {
            items
                .iter()
                .any(|item| item["call"]["call_id"] == call && item["call"]["phase"] == phase)
        })
    });
    pending
        .as_array()
        .unwrap()
        .iter()
        .find(|item| item["call"]["call_id"] == call && item["call"]["phase"] == phase)
        .unwrap()
        .clone()
}

#[test]
fn background_decline_and_active_hangup_use_the_current_authenticated_call() {
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
    let call = started["call_id"].as_str().unwrap();
    let incoming = call_entry(&mut callee, call, "incoming");
    let decline = &incoming["call"]["decline_capability"];
    let applied = callee.ask(json!({"action":"background_call_action", "capability":decline}));
    assert_eq!(applied["action"], "decline");
    call_entry(&mut caller, call, "ended");
    let started = caller.ask(json!({"action":"call_start","argument":id}));
    let call = started["call_id"].as_str().unwrap();
    call_entry(&mut callee, call, "incoming");
    callee.ask(json!({"action":"call_accept", "argument":id, "call_id":call}));
    let active = call_entry(&mut callee, call, "active");
    let hangup = &active["call"]["hangup_capability"];
    let applied = callee.ask(json!({"action":"background_call_action", "capability":hangup}));
    assert_eq!(applied["outcome"], "applied");
    assert_eq!(applied["action"], "hangup");
    let replay = callee.ask(json!({"action":"background_call_action", "capability":hangup}));
    assert_eq!(replay["outcome"], "stale");
    call_entry(&mut caller, call, "ended");
}

#[test]
#[ignore = "Requires an actual signed reachable public relay carrier."]
fn actual_waiting_carrier_receives_authenticated_call() {
    let _network = isolated_network_scenario();
    let mut caller = Peer::new_recorded_api();
    let mut callee = Peer::new_recorded_api();
    let carrier = Peer::new_recorded_api();
    let invite = caller.ask(json!({"action":"dm_invite"}));
    let id = invite["session_id"].as_str().unwrap();
    callee.ask(json!({"action":"dm_accept","argument":invite["invite_uri"]}));
    for peer in [&mut caller, &mut callee] {
        wait(peer, json!({"action":"dm_poll","argument":id}), |s| {
            s["state"] == "connected"
        });
    }
    caller.assert_bidirectional_dm_route(&mut callee, id);
    // Keep the caller an ordinary desktop node, without opting into waiting.
    callee.ask(json!({"action":"background_set","interactive":true,"waiting":true}));
    callee.ask(json!({"action":"background_set","interactive":false,"waiting":true}));
    let readiness = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        wait(&mut callee, json!({"action":"background_status"}), |s| {
            s["actual_mode"] == "waiting" && s["reachability"] == "ready"
        })
    }));
    let ready = match readiness {
        Ok(ready) => ready,
        Err(error) => {
            public_carrier_diagnostics(&mut caller, &mut callee, &carrier, id);
            std::panic::resume_unwind(error);
        }
    };
    assert_eq!(ready["attachment_count"], 1);
    let started = caller.ask(json!({"action":"call_start","argument":id}));
    let call = started["call_id"].as_str().unwrap();
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        call_entry(&mut callee, call, "incoming")
    }));
    let incoming = match result {
        Ok(incoming) => incoming,
        Err(error) => {
            public_carrier_diagnostics(&mut caller, &mut callee, &carrier, id);
            std::panic::resume_unwind(error);
        }
    };
    let decline = &incoming["call"]["decline_capability"];
    let applied = callee.ask(json!({"action":"background_call_action", "capability":decline}));
    assert_eq!(applied["outcome"], "applied");
    assert_eq!(applied["action"], "decline");
    wait(
        &mut caller,
        json!({"action":"dm_poll","argument":id}),
        |s| s["outgoing_call"].is_null() && s["active_call"].is_null(),
    );
}

fn public_carrier_diagnostics(caller: &mut Peer, callee: &mut Peer, carrier: &Peer, id: &str) {
    for (label, peer) in [("caller", &mut *caller), ("callee", &mut *callee)] {
        let snapshot = peer.ask(json!({"action":"dm_poll", "argument":id}));
        eprintln!(
            "{label} carrier diagnostic: {}",
            json!({"state":snapshot["state"], "mesh":snapshot["mesh"]})
        );
    }
    if let Some(directory) = std::env::var_os("MOSH_TEST_ARTIFACT_DIR") {
        let directory = std::path::PathBuf::from(directory);
        caller.archive_network_recording(&directory.join("caller"));
        callee.archive_network_recording(&directory.join("callee"));
        carrier.archive_network_recording(&directory.join("carrier"));
    }
}

#[test]
#[ignore]
fn independent_installation_process() {
    peer_process();
}
