use super::*;

fn text(snapshot: &Value, body: &str) -> Value {
    let messages: Vec<_> = snapshot["messages"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|message| message["body"] == body)
        .collect();
    assert_eq!(messages.len(), 1, "one copy of {body}, got {snapshot}");
    json!({
        "id": messages[0]["message_id"],
        "author": messages[0]["from_device"],
        "time": messages[0]["sent_at_ms"],
        "body": messages[0]["body"],
    })
}

pub(super) fn linked_dm(mut linked: Peer) -> (Peer, Peer, Peer, String) {
    let mut original = Peer::new();
    let mut contact = Peer::new();
    let invite = existing_dm(&mut original, &mut contact);
    let session = invite["session_id"].as_str().unwrap().to_owned();
    pair(&mut original, &mut linked);
    linked.connect(&contact);
    wait_connected(&mut linked, &mut contact, &session);
    let until = Instant::now() + Duration::from_secs(45);
    while linked.ask(json!({"action":"dm_poll","argument":session}))["history_sync"] != "complete" {
        assert!(Instant::now() < until, "initial history must complete");
        std::thread::sleep(Duration::from_millis(100));
    }
    (original, contact, linked, session)
}

#[test]
fn returning_desktop_recovers_missed_text_from_contact_after_source_restart() {
    let _network = isolated_network_scenario();
    let (mut original, mut contact, mut linked, session) = linked_dm(Peer::new());
    linked.stop();
    send(&mut original, &session, "Own text while offline");
    let own = contact.wait_dm_text(&session, "Own text while offline");
    send(&mut contact, &session, "Contact text while offline");
    let other = original.wait_dm_text(&session, "Contact text while offline");
    // The remaining holder did not send the own-device text and has no live
    // retransmission attempt for it. Recovery must use its retained history.
    original.stop();
    contact.restart();
    linked.restart();
    linked.connect(&contact);
    let recovered = linked.wait_dm_text(&session, "Own text while offline");
    assert_eq!(
        text(&recovered, "Own text while offline"),
        text(&own, "Own text while offline")
    );
    let recovered = linked.wait_dm_text(&session, "Contact text while offline");
    assert_eq!(
        text(&recovered, "Contact text while offline"),
        text(&other, "Contact text while offline")
    );
    send(&mut linked, &session, "After recovery from linked");
    contact.wait_dm_text(&session, "After recovery from linked");
    send(&mut contact, &session, "After recovery from contact");
    linked.wait_dm_text(&session, "After recovery from contact");
}

#[test]
fn recovery_switches_source_after_partial_import_and_restart_without_losing_live_text() {
    let _network = isolated_network_scenario();
    let (mut original, mut contact, mut linked, session) = linked_dm(Peer::new_manual_dm());
    linked.stop();
    for index in 0..40 {
        send(&mut original, &session, &format!("Missed {index}"));
    }
    let before = contact.wait_dm_text(&session, "Missed 39");
    original.stop();
    linked.restart();
    linked.connect(&contact);
    let partial = linked.wait_dm_text(&session, "Missed 0");
    assert_eq!(partial["history_sync"], "importing");
    assert!(partial["messages"].as_array().unwrap().len() < 41);
    contact.stop();
    linked.restart();
    original.restart();
    original.connect(&linked);
    send(&mut original, &session, "Live while switching source");
    linked.wait_dm_text(&session, "Live while switching source");
    let recovered = linked.wait_dm_text(&session, "Missed 39");
    for index in 0..40 {
        let body = format!("Missed {index}");
        assert_eq!(text(&recovered, &body), text(&before, &body));
    }
    text(&recovered, "Live while switching source");
    linked.restart();
    linked.connect(&original);
    let restored = linked.ask(json!({"action":"dm_poll","argument":session}));
    assert_eq!(restored["messages"].as_array().unwrap().len(), 42);
}

#[test]
fn returning_desktop_recovers_missed_epoch_from_a_holder_after_author_restart() {
    let _network = isolated_network_scenario();
    let (mut original, mut contact, mut linked, session) = linked_dm(Peer::new());
    linked.stop();
    let mut extra_contact_device = Peer::new();
    pair(&mut contact, &mut extra_contact_device);
    extra_contact_device.connect(&original);
    wait_connected(&mut extra_contact_device, &mut original, &session);
    send(&mut contact, &session, "Text in the missed epoch");
    let before = original.wait_dm_text(&session, "Text in the missed epoch");
    contact.stop();
    extra_contact_device.stop();
    original.restart();
    linked.restart();
    linked.connect(&original);
    let recovered = linked.wait_dm_text(&session, "Text in the missed epoch");
    assert_eq!(
        text(&recovered, "Text in the missed epoch"),
        text(&before, "Text in the missed epoch")
    );
    send(&mut linked, &session, "Recovered sender epoch");
    original.wait_dm_text(&session, "Recovered sender epoch");
    contact.restart();
    contact.connect(&linked);
    send(&mut linked, &session, "Recovered contact delivery");
    contact.wait_dm_text(&session, "Recovered contact delivery");
    send(&mut contact, &session, "Recovered contact response");
    linked.wait_dm_text(&session, "Recovered contact response");
}

fn add_contact_device(contact: &mut Peer, original: &mut Peer, session: &str) -> Peer {
    let mut extra = Peer::new();
    pair(contact, &mut extra);
    extra.connect(original);
    wait_connected(&mut extra, original, session);
    extra
}

#[test]
fn returning_desktop_applies_two_missed_epochs_after_other_devices_acknowledged_them() {
    let _network = isolated_network_scenario();
    let (mut original, mut contact, mut linked, session) = linked_dm(Peer::new());
    linked.stop();
    let mut first_extra = add_contact_device(&mut contact, &mut original, &session);
    let mut second_extra = add_contact_device(&mut contact, &mut original, &session);
    send(
        &mut first_extra,
        &session,
        "Existing leaf after roster update",
    );
    original.wait_dm_text(&session, "Existing leaf after roster update");
    send(&mut second_extra, &session, "After two missed epochs");
    let before = original.wait_dm_text(&session, "After two missed epochs");
    contact.stop();
    first_extra.stop();
    second_extra.stop();
    original.restart();
    linked.restart();
    linked.connect(&original);
    let recovered = linked.wait_dm_text(&session, "After two missed epochs");
    assert_eq!(
        text(&recovered, "After two missed epochs"),
        text(&before, "After two missed epochs")
    );
    contact.restart();
    contact.connect(&linked);
    send(&mut linked, &session, "Send after two epochs");
    contact.wait_dm_text(&session, "Send after two epochs");
    send(&mut contact, &session, "Reply after two epochs");
    linked.wait_dm_text(&session, "Reply after two epochs");
    original.wait_dm_text(&session, "Reply after two epochs");
}

#[test]
fn returning_desktop_waits_when_all_holders_are_offline_then_recovers_from_one() {
    let _network = isolated_network_scenario();
    let (mut original, mut contact, mut linked, session) = linked_dm(Peer::new());
    linked.stop();
    send(
        &mut original,
        &session,
        "Retained while every holder goes offline",
    );
    let before = contact.wait_dm_text(&session, "Retained while every holder goes offline");
    original.stop();
    contact.stop();
    linked.restart();
    let until = Instant::now() + Duration::from_secs(20);
    loop {
        let snapshot = linked.ask(json!({"action":"dm_poll","argument":session}));
        if snapshot["history_sync"] == "waiting_for_source" {
            assert_eq!(snapshot["messages"].as_array().unwrap().len(), 1);
            break;
        }
        assert!(
            Instant::now() < until,
            "unavailable holders must remain visible"
        );
        std::thread::sleep(Duration::from_millis(100));
    }
    linked.restart();
    contact.restart();
    contact.connect(&linked);
    let recovered = linked.wait_dm_text(&session, "Retained while every holder goes offline");
    assert_eq!(
        text(&recovered, "Retained while every holder goes offline"),
        text(&before, "Retained while every holder goes offline")
    );
}
