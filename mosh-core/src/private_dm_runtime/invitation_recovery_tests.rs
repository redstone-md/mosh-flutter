use super::*;

#[test]
fn consumed_invitation_retries_its_saved_welcome_after_restart() {
    let mut fixture = Fixture::new();
    let invitation = fixture.create();
    let mut bob = fixture.bob();
    fixture.net.drop_frames(ALICE_ID, BOB_ID, |_, body| {
        String::from_utf8_lossy(body).contains("Welcome")
    });
    accept(&mut bob, &invitation);
    fixture.runtime.service();
    assert!(
        !bob.poll_session(&invitation.session_id)
            .unwrap()
            .invite_available
    );
    assert!(!bob
        .session_ref(&invitation.session_id)
        .unwrap()
        .crypto
        .is_ready());
    fixture.restart();
    fixture.net.drop_frames(ALICE_ID, BOB_ID, |_, _| false);
    bob.session_mut(&invitation.session_id)
        .unwrap()
        .last_handshake_send_ms = 0;
    // A restarted creator can send Hello before the recipient retries its
    // package. Advance the existing Hello throttle without a wall-clock sleep.
    let resumed_at = now_ms();
    for round in 0..5 {
        let tick_at = resumed_at + round * HANDSHAKE_RESEND_MS;
        fixture.runtime.drain_inbound_at(tick_at);
        bob.drain_inbound_at(tick_at);
    }
    for runtime in [&fixture.runtime, &bob] {
        assert_eq!(
            runtime.session_ref(&invitation.session_id).unwrap().state,
            DmSessionState::Connected,
            "cached Welcome and timed Hello retries must reconnect both peers"
        );
    }
    assert_eq!(
        fixture
            .runtime
            .session_ref(&invitation.session_id)
            .unwrap()
            .crypto
            .member_count(),
        2
    );
}

#[test]
fn legacy_records_stay_visible_and_real_membership_keeps_consumption_without_history() {
    let mut fixture = Fixture::new();
    let invitation = fixture.create();
    let mut bob = fixture.bob();
    accept(&mut bob, &invitation);
    fixture.runtime.service();
    let bytes = fixture.store.list_sessions().unwrap().pop().unwrap();
    let mut record: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    record.as_object_mut().unwrap().remove("invitation");
    fixture
        .store
        .put_session(
            &invitation.session_id,
            &serde_json::to_vec(&record).unwrap(),
        )
        .unwrap();
    fixture.restart();
    let restored = fixture.runtime.list_sessions().unwrap().sessions;
    assert_eq!(restored.len(), 1);
    assert!(restored[0].messages.is_empty());
    assert!(!restored[0].invite_available);
    assert!(fixture
        .runtime
        .replace_invite(&invitation.session_id)
        .is_err());
}

#[test]
fn already_received_admission_wins_a_replace_race() {
    let mut fixture = Fixture::new();
    let invitation = fixture.create();
    let mut bob = fixture.bob();
    accept(&mut bob, &invitation);
    assert!(fixture
        .runtime
        .replace_invite(&invitation.session_id)
        .is_err());
    connect(&mut fixture.runtime, &mut bob, &invitation.session_id);
    assert_eq!(fixture.runtime.list_sessions().unwrap().sessions.len(), 1);
}

#[test]
fn a_second_independent_counterpart_cannot_use_a_consumed_invitation_after_restart() {
    let mut fixture = Fixture::new();
    let invitation = fixture.create();
    let mut bob = fixture.bob();
    accept(&mut bob, &invitation);
    fixture.runtime.service();
    fixture.restart();
    let mut outsider = PrivateDmRuntime::with_transport(
        fixture.net.endpoint("outsider"),
        fixture.attachments.clone(),
        None,
    );
    fixture
        .net
        .link_both(ALICE_ID, "outsider", PeerTransport::Direct);
    accept(&mut outsider, &invitation);
    let payload = outsider
        .session_ref(&invitation.session_id)
        .unwrap()
        .pending_key_package
        .clone()
        .unwrap();
    let session = fixture.runtime.session_mut(&invitation.session_id).unwrap();
    assert!(matches!(
        session.handle_control(payload),
        Err(PrivateDmRuntimeError::InvalidInvite(_))
    ));
    assert_eq!(session.crypto.member_count(), 2);
    assert_eq!(session.peer_display_name.as_deref(), Some("Bob"));
}

#[test]
fn refused_hidden_creation_leaves_no_durable_invitation() {
    let mut fixture = Fixture::new();
    let fault = fixture.store.refuse_record_writes(DM_HISTORY);
    let result = fixture.runtime.create_pending_invite(StartSessionRequest {
        display_name: "Alice".into(),
        listen_port: 0,
        static_peer: None,
    });
    assert!(matches!(result, Err(PrivateDmRuntimeError::Persistence(_))));
    drop(fault);
    fixture.restart();
    assert!(fixture.runtime.list_pending_invites().unwrap().is_empty());
    assert!(fixture.runtime.list_sessions().unwrap().sessions.is_empty());
}
