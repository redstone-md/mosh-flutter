use super::*;

fn restored_pair(legacy: bool) -> (Fixture, InviteCreated, Vec<u8>, PrivateDmRuntime) {
    let mut fixture = Fixture::new();
    let invitation = fixture
        .runtime
        .create_invite(StartSessionRequest {
            display_name: "Alice".into(),
            listen_port: 0,
            static_peer: None,
        })
        .unwrap();
    let mut bob = fixture.bob();
    accept(&mut bob, &invitation);
    let package = bob
        .session_ref(&invitation.session_id)
        .unwrap()
        .pending_key_package
        .clone()
        .unwrap();
    connect(&mut fixture.runtime, &mut bob, &invitation.session_id);
    bob.send_message(&invitation.session_id, "known contact".into())
        .unwrap();
    fixture.runtime.service();
    if legacy {
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
    }
    fixture.restart();
    (fixture, invitation, package, bob)
}

fn publish_package(fixture: &mut Fixture, invitation: &InviteCreated, payload: &[u8]) {
    fixture
        .net
        .link("outsider", ALICE_ID, PeerTransport::Direct);
    fixture
        .net
        .endpoint("outsider")
        .publish(
            &invitation.mesh_id,
            &control_channel(&invitation.session_id),
            payload,
        )
        .unwrap();
    fixture.runtime.service();
}

fn assert_original_contact(fixture: &mut Fixture, invitation: &InviteCreated) {
    let snapshot = fixture
        .runtime
        .poll_session(&invitation.session_id)
        .unwrap();
    assert_eq!(snapshot.peer_display_name, "Bob");
    assert_eq!(snapshot.peer_moss_id.as_deref(), Some(BOB_ID));
    assert_eq!(snapshot.transport, PeerTransport::Direct);
    assert!(!snapshot.invite_available);
    assert_eq!(snapshot.messages.len(), 1);
    assert_eq!(snapshot.messages[0].body, "known contact");
    assert_eq!(fixture.runtime.list_sessions().unwrap().sessions.len(), 1);
}

#[test]
fn restored_legacy_admission_rejects_an_outsider_without_changing_contact_or_route() {
    let (mut fixture, invitation, _, _bob) = restored_pair(true);
    assert_original_contact(&mut fixture, &invitation);
    let mut crypto = MlsSessionCrypto::new("Mallory").unwrap();
    let forged = serde_json::to_vec(&ControlEnvelope::KeyPackage {
        session_id: invitation.session_id.clone(),
        participant_id: "outsider".into(),
        from_device: "Mallory".into(),
        key_package_b64: encode(&crypto.key_package_bytes().unwrap()),
        moss_peer_id: Some("c".repeat(64)),
    })
    .unwrap();
    publish_package(&mut fixture, &invitation, &forged);
    assert_original_contact(&mut fixture, &invitation);
    fixture.restart();
    assert_original_contact(&mut fixture, &invitation);
}

#[test]
fn restored_legacy_contact_package_retries_preserve_identity_and_route_even_when_rewrapped() {
    let (mut fixture, invitation, original, _bob) = restored_pair(true);
    publish_package(&mut fixture, &invitation, &original);
    assert_original_contact(&mut fixture, &invitation);
    let mut replay: serde_json::Value = serde_json::from_slice(&original).unwrap();
    replay["from_device"] = serde_json::json!("Mallory");
    replay["moss_peer_id"] = serde_json::json!("c".repeat(64));
    publish_package(
        &mut fixture,
        &invitation,
        &serde_json::to_vec(&replay).unwrap(),
    );
    assert_original_contact(&mut fixture, &invitation);
    fixture.restart();
    assert_original_contact(&mut fixture, &invitation);
}

#[test]
fn consumed_manual_invitation_package_replay_cannot_overwrite_contact_metadata() {
    let (mut fixture, invitation, original, _bob) = restored_pair(false);
    publish_package(&mut fixture, &invitation, &original);
    assert_original_contact(&mut fixture, &invitation);
    let mut replay: serde_json::Value = serde_json::from_slice(&original).unwrap();
    replay["from_device"] = serde_json::json!("Mallory");
    replay["moss_peer_id"] = serde_json::json!("c".repeat(64));
    publish_package(
        &mut fixture,
        &invitation,
        &serde_json::to_vec(&replay).unwrap(),
    );
    assert_original_contact(&mut fixture, &invitation);
    fixture.restart();
    assert_original_contact(&mut fixture, &invitation);
}
