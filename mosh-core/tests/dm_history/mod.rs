use super::{existing_dm, pair, send, wait_connected};
use crate::link_support::{isolated_network_scenario, Peer};
use serde_json::{json, Value};
use std::time::{Duration, Instant};

fn text(snapshot: &Value, body: &str) -> Value {
    let matching: Vec<_> = snapshot["messages"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|message| message["body"] == body)
        .collect();
    assert_eq!(matching.len(), 1, "one copy of {body}, got {snapshot}");
    let message = matching[0];
    json!({
        "message_id":message["message_id"], "sent_at_ms":message["sent_at_ms"],
        "from_device":message["from_device"], "body":message["body"]
    })
}

fn admit_without_importing(
    original: &mut Peer,
    linked: &mut Peer,
    contact: &mut Peer,
    session: &str,
) {
    let until = Instant::now() + Duration::from_secs(45);
    loop {
        original.ask(json!({"action":"dm_list"}));
        contact.ask(json!({"action":"dm_poll","argument":session}));
        let list = linked.ask(json!({"action":"dm_list"}));
        if list["sessions"]
            .as_array()
            .unwrap()
            .iter()
            .any(|snapshot| snapshot["session_id"] == session && snapshot["state"] != "pending")
        {
            return;
        }
        assert!(
            Instant::now() < until,
            "linked device must be independently admitted"
        );
        std::thread::sleep(Duration::from_millis(100));
    }
}

fn finish_history(original: &mut Peer, linked: &mut Peer, session: &str) -> Value {
    let until = Instant::now() + Duration::from_secs(45);
    loop {
        original.ask(json!({"action":"dm_poll","argument":session}));
        let snapshot = linked.ask(json!({"action":"dm_poll","argument":session}));
        if snapshot["history_sync"] == "complete" {
            return snapshot;
        }
        assert!(
            Instant::now() < until,
            "history must resume, got {}",
            snapshot["history_sync"]
        );
        std::thread::sleep(Duration::from_millis(100));
    }
}

#[test]
fn linked_desktop_imports_pre_link_text_with_original_ids_authors_and_times() {
    let _network = isolated_network_scenario();
    let mut original = Peer::new();
    let mut counterpart = Peer::new();
    let mut linked = Peer::new();
    let invite = existing_dm(&mut original, &mut counterpart);
    let session = invite["session_id"].as_str().unwrap();
    send(&mut original, session, "Original history");
    counterpart.wait_dm_text(session, "Original history");
    let before = original.ask(json!({"action":"dm_poll","argument":session}));
    pair(&mut original, &mut linked);
    linked.connect(&counterpart);
    wait_connected(&mut linked, &mut counterpart, session);
    let imported = linked.wait_dm_text(session, "Before pairing");
    assert_eq!(
        text(&imported, "Before pairing"),
        text(&before, "Before pairing")
    );
    let imported = linked.wait_dm_text(session, "Original history");
    assert_eq!(
        text(&imported, "Original history"),
        text(&before, "Original history")
    );
    assert_eq!(imported["fingerprint"], before["fingerprint"]);
    assert_eq!(imported["history_sync"], "complete");
    linked.restart();
    linked.connect(&counterpart);
    let restored = finish_history(&mut original, &mut linked, session);
    assert_eq!(
        text(&restored, "Before pairing"),
        text(&before, "Before pairing")
    );
    assert_eq!(
        text(&restored, "Original history"),
        text(&before, "Original history")
    );
}

#[test]
fn interrupted_history_waits_for_source_resumes_and_keeps_live_text_once() {
    let _network = isolated_network_scenario();
    let mut original = Peer::new_manual_dm();
    let mut counterpart = Peer::new();
    let mut linked = Peer::new_manual_dm();
    let invite = existing_dm(&mut original, &mut counterpart);
    let session = invite["session_id"].as_str().unwrap();
    for index in 0..40 {
        send(&mut original, session, &format!("History {index}"));
    }
    counterpart.wait_dm_text(session, "History 39");
    let before = original.ask(json!({"action":"dm_poll","argument":session}));
    pair(&mut original, &mut linked);
    linked.connect(&counterpart);
    admit_without_importing(&mut original, &mut linked, &mut counterpart, session);
    original.stop();
    wait_connected(&mut linked, &mut counterpart, session);
    let waiting = linked.ask(json!({"action":"dm_poll","argument":session}));
    assert_eq!(waiting["history_sync"], "waiting_for_source");
    send(&mut counterpart, session, "Live during import");
    linked.wait_dm_text(session, "Live during import");
    original.restart();
    original.connect(&linked);
    original.connect(&counterpart);
    std::thread::sleep(Duration::from_millis(2100));
    linked.ask(json!({"action":"dm_poll","argument":session}));
    original.ask(json!({"action":"dm_poll","argument":session}));
    let partial = linked.wait_dm_text(session, "Before pairing");
    // The activity notice can expire while the partial history stays durable.
    assert!(matches!(
        partial["history_sync"].as_str(),
        Some("importing" | "waiting_for_source")
    ));
    assert!(partial["messages"].as_array().unwrap().len() < 42);
    original.stop();
    linked.restart();
    linked.connect(&counterpart);
    let restored = linked.ask(json!({"action":"dm_poll","argument":session}));
    assert_eq!(restored["history_sync"], "waiting_for_source");
    assert_eq!(
        text(&restored, "Before pairing"),
        text(&before, "Before pairing")
    );
    text(&restored, "Live during import");
    original.restart();
    original.connect(&linked);
    original.connect(&counterpart);
    send(&mut original, session, "Live after restart");
    let imported = finish_history(&mut original, &mut linked, session);
    assert_eq!(imported["messages"].as_array().unwrap().len(), 43);
    for index in 0..40 {
        let body = format!("History {index}");
        assert_eq!(text(&imported, &body), text(&before, &body));
    }
    text(&imported, "Live during import");
    text(&imported, "Live after restart");
    for _ in 0..3 {
        original.ask(json!({"action":"dm_poll","argument":session}));
    }
    linked.restart();
    let final_history = finish_history(&mut original, &mut linked, session);
    assert_eq!(final_history["messages"].as_array().unwrap().len(), 43);
}

#[test]
fn history_transfers_text_larger_than_a_signed_packet_without_changing_it() {
    let _network = isolated_network_scenario();
    let mut original = Peer::new();
    let mut counterpart = Peer::new();
    let mut linked = Peer::new();
    let invite = existing_dm(&mut original, &mut counterpart);
    let session = invite["session_id"].as_str().unwrap();
    let body = "Snow: ☃\n".repeat(20_000);
    send(&mut original, session, &body);
    let before = original.ask(json!({"action":"dm_poll","argument":session}));
    pair(&mut original, &mut linked);
    linked.connect(&counterpart);
    wait_connected(&mut linked, &mut counterpart, session);
    let imported = finish_history(&mut original, &mut linked, session);
    assert_eq!(text(&imported, &body), text(&before, &body));
    linked.restart();
    let restored = finish_history(&mut original, &mut linked, session);
    assert_eq!(text(&restored, &body), text(&before, &body));
}
