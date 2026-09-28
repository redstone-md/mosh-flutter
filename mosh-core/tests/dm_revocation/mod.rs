use super::*;
mod sync;

#[test]
fn offline_participant_keeps_removal_pending_then_dm_continues_without_revoked_device() {
    let _network = isolated_network_scenario();
    let mut original = Peer::new();
    let mut contact = Peer::new();
    let mut linked = Peer::new();
    let invite = existing_dm(&mut original, &mut contact);
    let session = invite["session_id"].as_str().unwrap();
    pair(&mut original, &mut linked);
    linked.connect(&contact);
    wait_connected(&mut linked, &mut contact, session);
    linked.wait_dm_text(session, "Before pairing");
    let device = linked.ask(json!({"action":"snapshot"}))["own_device_id"].clone();
    contact.stop();
    let revoked = original.ask(json!({"action":"revoke","argument":device}));
    assert_eq!(revoked["revocations"][0]["state"], "Pending");
    original.restart();
    assert_eq!(
        original.ask(json!({"action":"snapshot"}))["revocations"][0]["state"],
        "Pending"
    );
    contact.restart();
    original.connect(&contact);
    wait_applied(&mut original, &mut contact, session);
    send(&mut original, session, "Protected after removal");
    contact.wait_dm_text(session, "Protected after removal");
    send(&mut contact, session, "Honest participant recovered");
    original.wait_dm_text(session, "Honest participant recovered");
    let protected =
        original.ask(json!({"action":"crypto_encrypt","argument":session,"body":"Crypto proof"}));
    assert_eq!(protected["members"], 2);
    let readable = contact.ask(
        json!({"action":"crypto_decrypt","argument":session,"ciphertext":protected["ciphertext"]}),
    );
    assert_eq!(readable["plaintext"], "Crypto proof");
    let refused = linked.ask(
        json!({"action":"crypto_decrypt","argument":session,"ciphertext":protected["ciphertext"]}),
    );
    assert!(
        refused["error"].is_string(),
        "the removed MLS state must refuse the actual new ciphertext"
    );
    let refused_send =
        linked.ask(json!({"action":"dm_try_send","argument":session,"body":"Revoked sender"}));
    assert!(refused_send["error"].as_str().unwrap().contains("revoked"));
    let archive = linked.ask(json!({"action":"dm_poll","argument":session}));
    assert_eq!(archive["device_revocation"], "revoked");
    let messages = archive["messages"].as_array().unwrap();
    assert!(messages.iter().any(|m| m["body"] == "Before pairing"));
    assert!(!messages
        .iter()
        .any(|m| m["body"] == "Protected after removal"));
    linked.restart();
    assert_eq!(
        linked.ask(json!({"action":"dm_poll","argument":session}))["device_revocation"],
        "revoked"
    );
    pair(&mut original, &mut linked);
    linked.connect(&contact);
    let until = Instant::now() + Duration::from_secs(30);
    loop {
        let restored = linked.ask(json!({"action":"dm_poll","argument":session}));
        if restored["device_revocation"] != "revoked" && restored["state"] == "connected" {
            assert!(restored["messages"]
                .as_array()
                .unwrap()
                .iter()
                .any(|m| m["body"] == "Before pairing"));
            break;
        }
        assert!(
            Instant::now() < until,
            "fresh permission must admit a new MLS client and retain history"
        );
        std::thread::sleep(Duration::from_millis(100));
    }
    send(&mut linked, session, "Freshly authorized sender");
    contact.wait_dm_text(session, "Freshly authorized sender");
    send(&mut contact, session, "Reply after fresh permission");
    linked.wait_dm_text(session, "Reply after fresh permission");
}

fn wait_applied(original: &mut Peer, contact: &mut Peer, session: &str) {
    let until = Instant::now() + Duration::from_secs(45);
    loop {
        contact.ask(json!({"action":"dm_poll","argument":session}));
        let status = original.ask(json!({"action":"snapshot"}));
        if status["revocations"][0]["state"] == "Applied" {
            return;
        }
        assert!(
            Instant::now() < until,
            "remaining participant must durably apply removal: {status}"
        );
        std::thread::sleep(Duration::from_millis(100));
    }
}

#[test]
fn returning_participant_recovers_add_then_remove_from_holder_without_original_author() {
    let _network = isolated_network_scenario();
    let (mut original, mut contact, mut linked, session) = dm_recovery::linked_dm(Peer::new());
    linked.stop();
    let mut extra = Peer::new();
    pair(&mut contact, &mut extra);
    extra.connect(&original);
    wait_connected(&mut extra, &mut original, &session);
    send(&mut extra, &session, "Before missed removal");
    original.wait_dm_text(&session, "Before missed removal");
    let target = extra.ask(json!({"action":"snapshot"}))["own_device_id"].clone();
    contact.ask(json!({"action":"revoke","argument":target}));
    send(&mut contact, &session, "After missed removal");
    original.wait_dm_text(&session, "After missed removal");
    contact.stop();
    extra.stop();
    original.restart();
    linked.restart();
    linked.connect(&original);
    linked.wait_dm_text(&session, "After missed removal");
    send(&mut linked, &session, "Recovered removal epoch");
    original.wait_dm_text(&session, "Recovered removal epoch");
    contact.restart();
    contact.connect(&linked);
    wait_applied(&mut contact, &mut linked, &session);
    send(&mut contact, &session, "Author returns after recovery");
    linked.wait_dm_text(&session, "Author returns after recovery");
}
