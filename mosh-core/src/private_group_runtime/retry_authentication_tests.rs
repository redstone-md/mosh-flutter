use super::*;
use crate::sender_auth::SenderProof;

fn saved_wire(fixture: &Fixture, id: &str) -> DataEnvelope {
    let attempt = fixture
        .store
        .get_outbound_attempt(GROUP_HISTORY.outbound_scope, &fixture.id, id)
        .unwrap()
        .unwrap();
    let attempt: OutboundAttemptRecord = serde_json::from_slice(&attempt).unwrap();
    let proof: SenderProof =
        serde_json::from_slice(&decode(&attempt.publish_payload_b64).unwrap()).unwrap();
    let session = fixture.runtime.groups.get(&fixture.id).unwrap();
    let sender = proof
        .verify(&OrgContext {
            org_pubkey: "",
            mesh_id: &session.mesh_id,
            channel_kind: &session.data_channel,
        })
        .unwrap();
    serde_json::from_slice(&sender.payload).unwrap()
}

fn legacy_outbound_attempt() -> (Fixture, MlsSessionCrypto, GroupSendResult) {
    let mut fixture = Fixture::new();
    let mut peer = MlsSessionCrypto::new("Bob").unwrap();
    let package = peer.key_package_bytes().unwrap();
    let outcome = fixture
        .runtime
        .groups
        .get_mut(&fixture.id)
        .unwrap()
        .crypto
        .add_members(&[&package])
        .unwrap();
    peer.join_welcome(&outcome.welcome_bytes, &outcome.tree_bytes)
        .unwrap();
    let _failure = fixture.refuse_data_publication("first attempt refused");
    let sent = fixture
        .runtime
        .send(&fixture.id, "legacy retry".into())
        .unwrap();
    let legacy = saved_wire(&fixture, &sent.message_id);
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    session
        .outbound_attempts
        .get_mut(&sent.message_id)
        .unwrap()
        .publish_payload_b64 = encode(&serde_json::to_vec(&legacy).unwrap());
    fixture
        .runtime
        .groups
        .persist_send(&fixture.id, &sent.message_id, true)
        .unwrap();
    (fixture, peer, sent)
}

#[test]
fn legacy_retry_survives_a_refused_snapshot_and_restart_without_reusing_a_generation() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let (mut fixture, mut peer, sent) = legacy_outbound_attempt();
    fixture.restart();
    let fault = fixture.store.refuse_group_snapshot_writes();
    let _deferred = fixture.refuse_data_publication("deferred until checkpoint");
    assert!(matches!(
        fixture.runtime.retry_message(&fixture.id, &sent.message_id),
        Err(PrivateGroupError::Persistence(_))
    ));
    drop(fault);
    fixture.restart();
    let retried = fixture
        .runtime
        .retry_message(&fixture.id, &sent.message_id)
        .unwrap();
    assert_eq!(retried.message_id, sent.message_id);
    assert_eq!(retried.sent_at_ms, sent.sent_at_ms);
    assert_eq!(retried.delivery_status, MessageDeliveryStatus::Failed);
    assert!(retried
        .delivery_error
        .unwrap()
        .contains("deferred until checkpoint"));
    let wire = saved_wire(&fixture, &sent.message_id);
    assert_eq!(
        peer.decrypt(&decode(&wire.ciphertext_b64).unwrap())
            .unwrap(),
        b"legacy retry"
    );
    fixture.restart();
    let _failure = fixture.refuse_data_publication("inspect next generation");
    let next = fixture
        .runtime
        .send(&fixture.id, "after restart".into())
        .unwrap();
    let wire = saved_wire(&fixture, &next.message_id);
    assert_eq!(
        peer.decrypt(&decode(&wire.ciphertext_b64).unwrap())
            .unwrap(),
        b"after restart"
    );
    assert_eq!(fixture.runtime.poll(&fixture.id).unwrap().messages.len(), 2);
}
