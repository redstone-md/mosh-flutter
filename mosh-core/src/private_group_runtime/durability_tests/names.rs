use super::*;
use crate::sender_auth::SenderProof;

#[test]
fn admin_rename_and_its_history_event_are_durable_before_acceptance() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let renamed = fixture
        .runtime
        .rename_group(&fixture.id, "  Работа  ")
        .unwrap();
    assert_eq!(renamed.label.as_deref(), Some("Работа"));
    assert_eq!(renamed.messages.len(), 1);
    assert_eq!(renamed.messages[0].from_device, "Alice");
    assert_eq!(
        renamed.messages[0].name_change.as_ref().unwrap().name,
        "Работа"
    );
    let event_id = renamed.messages[0].message_id.clone();
    fixture.restart();
    let restored = fixture.runtime.poll(&fixture.id).unwrap();
    assert_eq!(restored.label.as_deref(), Some("Работа"));
    assert_eq!(restored.messages.len(), 1);
    assert_eq!(restored.messages[0].message_id, event_id);
    assert!(fixture
        .runtime
        .rename_group(&fixture.id, "Bad\nName")
        .is_err());
    assert_eq!(
        fixture.runtime.poll(&fixture.id).unwrap().label.as_deref(),
        Some("Работа")
    );
}

pub(super) fn admitted_pair() -> (Fixture, Fixture) {
    let mut admin = Fixture::new();
    let invite = admin.runtime.poll(&admin.id).unwrap().invite_uri.unwrap();
    let mut member = Fixture::empty();
    member.join(&invite, "Bob");
    let session = admin.runtime.groups.get_mut(&admin.id).unwrap();
    member.deliver_welcome(&mut session.crypto);
    assert_eq!(member.runtime.poll(&member.id).unwrap().state, "ready");
    admin.runtime.poll(&admin.id).unwrap();
    (admin, member)
}

fn deliver_handoff(admin: &mut Fixture, member: &mut Fixture) {
    let session = admin.runtime.groups.get_mut(&admin.id).unwrap();
    let proof = session.name_handoff_proof().unwrap().unwrap();
    let channel = member
        .runtime
        .groups
        .get(&member.id)
        .unwrap()
        .control_channel
        .clone();
    inbox::deliver(MossReceivedMessage {
        channel,
        payload: decode(&proof).unwrap(),
    });
}

#[test]
fn shared_name_recovers_for_member_and_member_cannot_rename() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let (mut admin, mut member) = admitted_pair();
    let accepted = admin.runtime.rename_group(&admin.id, "Plans").unwrap();
    assert!(accepted.name_status.unwrap().pending);
    admin.restart();
    assert!(
        admin
            .runtime
            .poll(&admin.id)
            .unwrap()
            .name_status
            .unwrap()
            .pending
    );
    assert!(matches!(
        member.runtime.rename_group(&member.id, "Forged"),
        Err(PrivateGroupError::RenameDenied)
    ));
    deliver_handoff(&mut admin, &mut member);
    let received = member.runtime.poll(&member.id).unwrap();
    assert_eq!(received.label.as_deref(), Some("Plans"));
    assert_eq!(received.messages[0].from_device, "Alice");
    member.restart();
    assert_eq!(
        member.runtime.poll(&member.id).unwrap().label.as_deref(),
        Some("Plans")
    );
}

#[test]
fn departure_carries_latest_name_to_successor_before_removing_admin() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let (mut admin, mut member) = admitted_pair();
    admin
        .runtime
        .rename_group(&admin.id, "After departure")
        .unwrap();
    let session = admin.runtime.groups.get_mut(&admin.id).unwrap();
    let proof = session.name_handoff_proof().unwrap();
    let envelope = ControlEnvelope::SelfRemove {
        group_id: admin.id.clone(),
        from_fingerprint: session.crypto.fingerprint(),
        proposal_b64: encode(&session.crypto.leave_proposal_bytes().unwrap()),
        name_state_proof_b64: proof,
    };
    let channel = member
        .runtime
        .groups
        .get(&member.id)
        .unwrap()
        .control_channel
        .clone();
    inbox::deliver(MossReceivedMessage {
        channel,
        payload: serde_json::to_vec(&envelope).unwrap(),
    });
    let successor = member.runtime.poll(&member.id).unwrap();
    assert!(successor.is_admin);
    assert_eq!(successor.label.as_deref(), Some("After departure"));
    assert_eq!(
        member
            .runtime
            .rename_group(&member.id, "Successor name")
            .unwrap()
            .label
            .as_deref(),
        Some("Successor name")
    );
}

#[test]
fn refused_name_transaction_preserves_name_history_and_restart() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let fault = fixture.store.refuse_message_writes(GROUP_HISTORY);
    assert!(matches!(
        fixture.runtime.rename_group(&fixture.id, "Refused"),
        Err(PrivateGroupError::Persistence(_))
    ));
    drop(fault);
    let snapshot = fixture.runtime.poll(&fixture.id).unwrap();
    assert_eq!(snapshot.label.as_deref(), Some("Durable Group"));
    assert!(snapshot.messages.is_empty());
    fixture.restart();
    assert_eq!(
        fixture.runtime.poll(&fixture.id).unwrap().label.as_deref(),
        Some("Durable Group")
    );
}

pub(super) fn create_org_group(fixture: &mut Fixture, org: &str, display_name: &str) {
    let transport = SigningKey::from_bytes(&[17; 32]);
    let mut blob = vec![1];
    blob.extend_from_slice(&transport.to_bytes());
    blob.extend_from_slice(transport.verifying_key().as_bytes());
    blob.extend_from_slice(&[0; 64]);
    fixture.store.put_moss_identity(&blob).unwrap();
    fixture.id = fixture
        .runtime
        .create_group(CreateGroupRequest {
            label: Some("Durable Group".into()),
            display_name: display_name.into(),
            listen_port: 42247,
            static_peer: None,
            org_pubkey: Some(org.into()),
        })
        .unwrap()
        .group_id;
}

pub(super) fn delayed_org_ack(
    fixture: &Fixture,
    snapshot: &GroupSnapshot,
    member: &MlsSessionCrypto,
) -> MossReceivedMessage {
    let session = fixture.runtime.groups.get(&fixture.id).unwrap();
    let id = snapshot
        .messages
        .last()
        .unwrap()
        .message_id
        .as_ref()
        .unwrap();
    let parts: Vec<_> = id.split(':').collect();
    let ack = serde_json::json!({"Ack":{"epoch":parts[1].parse::<u64>().unwrap(),
        "roster_version":parts[2].parse::<u64>().unwrap(), "counter":parts[3].parse::<u64>().unwrap(), "actor":parts[4]}});
    let envelope = ControlEnvelope::NameMetadata {
        group_id: fixture.id.clone(),
        operation: crate::private_group_runtime::names::NameOperation::Ack,
        epoch: member.epoch().unwrap(),
        ciphertext_b64: session.seal_name(&ack).unwrap(),
    };
    let key = SigningKey::from_bytes(&[72; 32]);
    let context = OrgContext {
        org_pubkey: session.org_pubkey.as_deref().unwrap(),
        mesh_id: &session.mesh_id,
        channel_kind: &session.control_channel,
    };
    let proof = SenderProof::sign(
        &key,
        member,
        &context,
        serde_json::to_vec(&envelope).unwrap(),
    )
    .unwrap();
    let packet = org_envelope::sign(&key, &context, &serde_json::to_vec(&proof).unwrap());
    MossReceivedMessage {
        channel: session.control_channel.clone(),
        payload: serde_json::to_vec(&packet).unwrap(),
    }
}

#[test]
fn verified_org_role_overrides_creator_flag_and_demoted_pending_name_rolls_back() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::empty();
    let key = SigningKey::from_bytes(&[61; 32]);
    let org = hex::encode(key.verifying_key().as_bytes());
    create_org_group(&mut fixture, &org, "Alice");
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    let peer = session.own_peer_id().unwrap();
    let bob_peer = hex::encode(SigningKey::from_bytes(&[72; 32]).verifying_key().as_bytes());
    let mut bob = MlsSessionCrypto::new(&bob_peer).unwrap();
    let admission = session
        .crypto
        .add_members(&[&bob.key_package_bytes().unwrap()])
        .unwrap();
    bob.join_welcome(&admission.welcome_bytes, &admission.tree_bytes)
        .unwrap();
    let put_role = |version, role| {
        let mut doc = serde_json::json!({"org_pubkey": org, "org_name": "Org", "version": version,
            "members": [{"moss_peer_id": peer, "name":"Alice", "role":role},
                {"moss_peer_id": bob_peer, "name":"Bob", "role":"member"}]});
        let bytes = org_roster::sign_roster(&mut doc, &key).unwrap();
        fixture.store.put_org_roster(&org, &bytes).unwrap();
    };
    put_role(1, "admin");
    let renamed = fixture
        .runtime
        .rename_group(&fixture.id, "Offline change")
        .unwrap();
    let ack = delayed_org_ack(&fixture, &renamed, &bob);
    assert!(renamed.name_status.unwrap().pending);
    put_role(2, "member");
    inbox::deliver(ack);
    let snapshot = fixture.runtime.poll(&fixture.id).unwrap();
    assert!(!snapshot.is_admin);
    assert_eq!(snapshot.label.as_deref(), Some("Durable Group"));
    assert!(snapshot.name_status.unwrap().error.is_some());
    assert_eq!(
        snapshot.messages[0].delivery_status,
        Some(MessageDeliveryStatus::Failed)
    );
    assert!(matches!(
        fixture.runtime.rename_group(&fixture.id, "Denied"),
        Err(PrivateGroupError::RenameDenied)
    ));
    fixture.restart();
    assert_eq!(
        fixture.runtime.poll(&fixture.id).unwrap().label.as_deref(),
        Some("Durable Group")
    );
}

#[test]
fn skipped_metadata_does_not_break_legacy_messages_or_offline_name_recovery() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let (mut admin, mut offline) = admitted_pair();
    admin.runtime.rename_group(&admin.id, "Latest").unwrap();
    let session = admin.runtime.groups.get_mut(&admin.id).unwrap();
    for _ in 0..1005 {
        session.name_handoff_proof().unwrap();
    }
    // Keep the ordinary wire frame in the outbox for the offline receiver.
    let publication = admin.refuse_data_publication("capture ordinary frame");
    let sent = admin
        .runtime
        .send(&admin.id, "Ordinary message".into())
        .unwrap();
    drop(publication);
    let attempt = admin
        .store
        .get_outbound_attempt(GROUP_HISTORY.outbound_scope, &admin.id, &sent.message_id)
        .unwrap()
        .unwrap();
    let attempt: crate::outbound_delivery::OutboundAttemptRecord =
        serde_json::from_slice(&attempt).unwrap();
    let channel = offline
        .runtime
        .groups
        .get(&offline.id)
        .unwrap()
        .data_channel
        .clone();
    inbox::deliver(MossReceivedMessage {
        channel,
        payload: decode(&attempt.publish_payload_b64).unwrap(),
    });
    let received = offline.runtime.poll(&offline.id).unwrap();
    let text = received
        .messages
        .iter()
        .find(|message| message.message_id.as_deref() == Some(&sent.message_id))
        .unwrap();
    assert_eq!(text.body, "Ordinary message");
    deliver_handoff(&mut admin, &mut offline);
    assert_eq!(
        offline.runtime.poll(&offline.id).unwrap().label.as_deref(),
        Some("Latest")
    );
}

#[test]
fn only_acknowledged_revision_is_sent_and_earlier_attempt_is_superseded() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let (mut admin, mut member) = admitted_pair();
    admin.runtime.rename_group(&admin.id, "First").unwrap();
    let renamed = admin.runtime.rename_group(&admin.id, "Second").unwrap();
    assert_eq!(
        renamed.messages[0].delivery_error.as_deref(),
        Some("superseded")
    );
    assert_ne!(
        renamed.messages[0].delivery_status,
        Some(MessageDeliveryStatus::Sent)
    );
    deliver_handoff(&mut admin, &mut member);
    member.runtime.poll(&member.id).unwrap();
    let id = renamed.messages[1].message_id.as_ref().unwrap();
    let parts: Vec<_> = id.split(':').collect();
    let ack = serde_json::json!({"Ack":{"epoch":parts[1].parse::<u64>().unwrap(),
        "roster_version":parts[2].parse::<u64>().unwrap(), "counter":parts[3].parse::<u64>().unwrap(), "actor":parts[4]}});
    let session = member.runtime.groups.get_mut(&member.id).unwrap();
    let envelope = ControlEnvelope::NameMetadata {
        group_id: member.id.clone(),
        operation: crate::private_group_runtime::names::NameOperation::Ack,
        epoch: session.crypto.epoch().unwrap(),
        ciphertext_b64: session.seal_name(&ack).unwrap(),
    };
    let proof = session
        .sign_application(&envelope, &session.control_channel)
        .unwrap();
    inbox::deliver(MossReceivedMessage {
        channel: session.control_channel.clone(),
        payload: serde_json::to_vec(&proof).unwrap(),
    });
    let settled = admin.runtime.poll(&admin.id).unwrap();
    assert!(!settled.name_status.unwrap().pending);
    assert_eq!(
        settled.messages[0].delivery_status,
        Some(MessageDeliveryStatus::Failed)
    );
    assert_eq!(
        settled.messages[1].delivery_status,
        Some(MessageDeliveryStatus::Sent)
    );
}
