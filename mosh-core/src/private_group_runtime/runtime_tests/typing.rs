use super::*;

/// Cleo types, the member sees WHO types, the sender's message clears
/// the hint, and a forged hint is dead on arrival.
#[test]
fn group_typing_identifies_the_member_and_stops_on_their_message() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut view = MemberView::open(42395);

    // Cleo's hint lands: the snapshot names cleo (fingerprint + display
    // name) with a receiver-stamped deadline.
    view.deliver_cleo_typing();
    let member = view.typing_member_of().expect("cleo's hint must stand");
    assert_eq!(member.fingerprint, view.cleo.fingerprint());
    assert_eq!(member.display_name, "cleo");
    assert!(
        member.until_ms > now_ms(),
        "the deadline is stamped from the receiver's clock"
    );

    // A refresh renews the same entry (no duplicate rows for one member).
    view.deliver_cleo_typing();
    assert_eq!(view.session().typing_members_live().len(), 1);

    // Cleo's own message contradicts "typing": the hint dies at once.
    let body = b"cleo is done typing".to_vec();
    let ciphertext = view.cleo.encrypt(&body).unwrap();
    let data = DataEnvelope {
        group_id: view.group_id.clone(),
        participant_id: "cleo-participant".to_string(),
        from_device: "cleo".to_string(),
        from_fingerprint: view.cleo.fingerprint(),
        message_id: Some("g-typing-1".to_string()),
        sent_at_ms: Some(now_ms()),
        ciphertext_b64: encode(&ciphertext),
    };
    let session = view.runtime.groups.get_mut(&view.group_id).unwrap();
    session
        .handle_moss_message(MossReceivedMessage {
            channel: session.data_channel.clone(),
            payload: serde_json::to_vec(&data).unwrap(),
        })
        .expect("cleo's message should be handled");
    assert!(
        view.typing_member_of().is_none(),
        "a member's own message clears their hint"
    );
}

// A hint that never decrypts (an outsider's bytes) leaves the roster
// empty: the MLS decrypt is the only door, same as the DM side.
#[test]
fn a_forged_group_hint_is_dropped() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut view = MemberView::open(42396);
    view.deliver(&ControlEnvelope::TypingIndicator {
        group_id: view.group_id.clone(),
        from_device: "stranger".to_string(),
        from_fingerprint: "stranger-fingerprint".to_string(),
        typing_ciphertext_b64: encode(b"not-an-mls-ciphertext"),
    });
    assert!(view.typing_member_of().is_none());
}
