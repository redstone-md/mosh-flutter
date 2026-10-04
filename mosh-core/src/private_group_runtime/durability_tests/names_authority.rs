use super::*;

fn org_pair() -> (Fixture, String, Vec<u8>, MlsSessionCrypto) {
    let mut fixture = Fixture::empty();
    let root = SigningKey::from_bytes(&[61; 32]);
    let org = hex::encode(root.verifying_key().as_bytes());
    names::create_org_group(&mut fixture, &org, "Alice");
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    let bob_peer = hex::encode(SigningKey::from_bytes(&[72; 32]).verifying_key().as_bytes());
    let mut bob = MlsSessionCrypto::new(&bob_peer).unwrap();
    let admission = session
        .crypto
        .add_members(&[&bob.key_package_bytes().unwrap()])
        .unwrap();
    bob.join_welcome(&admission.welcome_bytes, &admission.tree_bytes)
        .unwrap();
    let mut doc = serde_json::json!({"org_pubkey": org, "org_name": "Org", "version": 1,
        "members": [{"moss_peer_id": session.own_peer_id().unwrap(), "name":"Alice", "role":"admin"},
            {"moss_peer_id": bob_peer, "name":"Bob", "role":"member"}]});
    let roster = org_roster::sign_roster(&mut doc, &root).unwrap();
    fixture.store.put_org_roster(&org, &roster).unwrap();
    (fixture, org, roster, bob)
}

#[test]
fn unavailable_org_authority_preserves_pending_name_across_restart_and_retry() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let (mut fixture, org, roster, bob) = org_pair();
    let accepted = fixture
        .runtime
        .rename_group(&fixture.id, "Pending name")
        .unwrap();
    let ack = names::delayed_org_ack(&fixture, &accepted, &bob);
    fixture
        .store
        .put_org_roster(&org, b"invalid roster")
        .unwrap();
    let snapshot = fixture.runtime.poll(&fixture.id).unwrap();
    assert_eq!(snapshot.label.as_deref(), Some("Pending name"));
    assert!(snapshot.name_status.unwrap().pending);
    assert!(!snapshot.is_admin);
    assert_eq!(
        snapshot.messages[0].delivery_status,
        Some(MessageDeliveryStatus::Queued)
    );
    fixture.restart();
    let snapshot = fixture.runtime.poll(&fixture.id).unwrap();
    assert_eq!(snapshot.label.as_deref(), Some("Pending name"));
    assert!(snapshot.name_status.unwrap().pending);
    fixture.store.put_org_roster(&org, &roster).unwrap();
    inbox::deliver(ack);
    let snapshot = fixture.runtime.poll(&fixture.id).unwrap();
    assert_eq!(snapshot.label.as_deref(), Some("Pending name"));
    assert!(!snapshot.name_status.unwrap().pending);
    assert!(snapshot.is_admin);
    assert_eq!(
        snapshot.messages[0].delivery_status,
        Some(MessageDeliveryStatus::Sent)
    );
}
