use super::*;

#[test]
fn a_repeated_key_package_replays_welcome_without_another_add() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let mut joiner = MlsSessionCrypto::new("Bob").unwrap();
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    let payload = serde_json::to_vec(&ControlEnvelope::KeyPackage {
        group_id: fixture.id.clone(),
        participant_id: "original-join-target".into(),
        from_device: "Bob".into(),
        from_fingerprint: "legacy-routing-hint".into(),
        key_package_b64: encode(&joiner.key_package_bytes().unwrap()),
        joiner_binding: None,
    })
    .unwrap();
    let fault = fail_next_test_publish_on(&session.control_channel, "lost original Welcome");
    assert!(session
        .handle_control(payload.clone(), None)
        .unwrap_err()
        .to_string()
        .contains("lost original Welcome"));
    drop(fault);
    assert_eq!(session.crypto.member_count(), 2);
    let epoch = session.crypto.epoch();
    let accepted = session.crypto.snapshot();
    let fault = fail_next_test_publish_on(&session.control_channel, "replayed original Welcome");
    let replay = session.handle_control(payload.clone(), None);
    assert!(
        replay
            .unwrap_err()
            .to_string()
            .contains("replayed original Welcome"),
        "the same KeyPackage must retry its saved Welcome instead of silently deduplicating"
    );
    drop(fault);
    assert_eq!(session.crypto.epoch(), epoch);
    assert_eq!(session.crypto.snapshot(), accepted);
    session.handle_control(payload, None).unwrap();
    assert_eq!(session.crypto.member_count(), 2);
    assert_eq!(session.crypto.epoch(), epoch);
}

#[test]
fn saved_welcome_survives_restart_and_keeps_its_original_target() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let mut joiner = MlsSessionCrypto::new("Bob").unwrap();
    let package = joiner.key_package_bytes().unwrap();
    let payload = |target: &str| {
        serde_json::to_vec(&ControlEnvelope::KeyPackage {
            group_id: fixture.id.clone(),
            participant_id: target.into(),
            from_device: "Bob".into(),
            from_fingerprint: "legacy-hint".into(),
            key_package_b64: encode(&package),
            joiner_binding: None,
        })
        .unwrap()
    };
    let original = payload("original-target");
    let tampered = payload("changed-target");
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    session.handle_control(original, None).unwrap();
    let key = session.admission_replay_key(&package);
    let saved = fixture
        .store
        .group_history_evidence::<serde_json::Value>(&key)
        .unwrap()
        .unwrap();
    let epoch = session.crypto.epoch();
    fixture.restart();
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    assert_eq!(session.crypto.epoch(), epoch);
    let snapshot = session.crypto.snapshot();
    assert!(session.admission_replays.is_empty());
    let fault = fail_next_test_publish_on(&session.control_channel, "durable original Welcome");
    assert!(session
        .handle_control(tampered, None)
        .unwrap_err()
        .to_string()
        .contains("durable original Welcome"));
    drop(fault);
    assert!(
        session.crypto.snapshot() == snapshot,
        "replay changed own MLS state"
    );
    assert_eq!(
        fixture
            .store
            .group_history_evidence::<serde_json::Value>(&key)
            .unwrap()
            .unwrap(),
        saved
    );
    let bytes: Vec<u8> = serde_json::from_value(saved["welcome"].clone()).unwrap();
    let welcome: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(welcome["for_participant_id"], "original-target");
}

#[test]
fn prepared_join_retries_the_original_package_with_a_bounded_cadence() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::empty();
    let mut admin = MlsSessionCrypto::new("Alice").unwrap();
    admin.create_group().unwrap();
    let invite = build_invite_uri("join-retry", "join-retry", &admin.fingerprint(), &None);
    fixture.join(&invite, "Bob");
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    let original = session.pending_join_package.clone();
    let snapshot = session.crypto.snapshot();
    let fault = fail_next_test_publish_on(&session.control_channel, "same KeyPackage retry");
    session.retry_pending_join().unwrap();
    std::thread::sleep(std::time::Duration::from_millis(3_050));
    assert!(session
        .retry_pending_join()
        .unwrap_err()
        .to_string()
        .contains("same KeyPackage retry"));
    drop(fault);
    session.retry_pending_join().unwrap();
    assert_eq!(session.pending_join_package, original);
    assert!(
        session.crypto.snapshot() == snapshot,
        "replay changed own MLS state"
    );
    assert!(!session.joined);
}

#[test]
fn supplied_admission_binding_is_not_ignored_before_installing_welcome() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::empty();
    let mut admin = MlsSessionCrypto::new("Alice").unwrap();
    admin.create_group().unwrap();
    let invite = build_invite_uri(
        "admission-mesh",
        "admission-group",
        &admin.fingerprint(),
        &None,
    );
    fixture.join(&invite, "Bob");
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    let package = session.pending_join_package.as_ref().unwrap();
    let admission = admin.add_members(&[package]).unwrap();
    let proof = crate::sender_auth::SenderProof::sign(
        &SigningKey::from_bytes(&[83; 32]),
        &admin,
        &OrgContext {
            org_pubkey: "",
            mesh_id: &session.mesh_id,
            channel_kind: &session.control_channel,
        },
        b"a genuine signature is not an admission association".to_vec(),
    )
    .unwrap();
    let mut welcome = serde_json::json!({
        "type": "Welcome", "group_id": fixture.id,
        "for_participant_id": session.participant_id,
        "from_fingerprint": admin.fingerprint(),
        "welcome_b64": encode(&admission.welcome_bytes),
        "tree_b64": encode(&admission.tree_bytes),
        "commit_b64": encode(&admission.commit_bytes),
        "admission_binding": proof,
    });
    let channel = session.control_channel.clone();
    inbox::deliver(MossReceivedMessage {
        channel: channel.clone(),
        payload: serde_json::to_vec(&welcome).unwrap(),
    });
    assert_eq!(
        fixture.runtime.poll(&fixture.id).unwrap().member_count,
        0,
        "an invalid supplied association must leave the original join retryable"
    );
    assert!(fixture
        .store
        .get_group_mls_snapshot(&fixture.id)
        .unwrap()
        .is_none());
    welcome.as_object_mut().unwrap().remove("admission_binding");
    inbox::deliver(MossReceivedMessage {
        channel,
        payload: serde_json::to_vec(&welcome).unwrap(),
    });
    assert_eq!(
        fixture.runtime.poll(&fixture.id).unwrap().member_count,
        2,
        "absent optional evidence retains legacy live compatibility"
    );
}
