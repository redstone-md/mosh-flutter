use super::*;
use crate::sender_auth::SenderProof;
use sha2::{Digest, Sha256};

#[test]
fn a_valid_signature_cannot_change_any_pinned_admission_association() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::empty();
    let mut admin = MlsSessionCrypto::new("Alice").unwrap();
    admin.create_group().unwrap();
    let invite = build_invite_uri(
        "exact-admission",
        "exact-admission",
        &admin.fingerprint(),
        &None,
    );
    fixture.join(&invite, "Bob");
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    let prior = admin.history_context().unwrap();
    let package = session.pending_join_package.as_ref().unwrap();
    let own_binding = crate::private_group_runtime::history::admission::joiner_binding(
        &session.node,
        &session.crypto,
        &session.to_persisted_record(),
        package,
    )
    .unwrap();
    let outcome = admin.add_members(&[package]).unwrap();
    let next = admin.history_context().unwrap();
    let digest = |bytes: &[u8]| hex::encode(Sha256::digest(bytes));
    let association = serde_json::json!([
        "mosh-history-admission-association-v1",
        1,
        session.deletions.context,
        session.mesh_id,
        null,
        hex::encode(&prior.group_id),
        [prior.epoch, prior.hash],
        [next.epoch, next.hash],
        digest(&outcome.commit_bytes),
        digest(&outcome.welcome_bytes),
        digest(&outcome.tree_bytes),
        hex::encode(session.crypto.signer_public()),
        digest(&serde_json::to_vec(&own_binding).unwrap()),
        now_ms(),
    ]);
    let issuer = SigningKey::from_bytes(&[82; 32]);
    let proof = |body: &serde_json::Value, crypto: &MlsSessionCrypto| {
        SenderProof::sign(
            &issuer,
            crypto,
            &OrgContext {
                org_pubkey: "",
                mesh_id: &session.mesh_id,
                channel_kind: &session.control_channel,
            },
            serde_json::to_vec(body).unwrap(),
        )
        .unwrap()
    };
    let envelope = |binding: SenderProof| {
        serde_json::to_vec(&ControlEnvelope::Welcome {
            group_id: fixture.id.clone(),
            for_participant_id: session.participant_id.clone(),
            from_fingerprint: admin.fingerprint(),
            welcome_b64: encode(&outcome.welcome_bytes),
            tree_b64: encode(&outcome.tree_bytes),
            commit_b64: encode(&outcome.commit_bytes),
            admission_binding: Some(binding),
        })
        .unwrap()
    };
    let attacks = [
        (0, serde_json::json!("another-domain")),
        (1, serde_json::json!(2)),
        (2, serde_json::json!("group:other")),
        (3, serde_json::json!("other-mesh")),
        (4, serde_json::json!("00".repeat(32))),
        (5, serde_json::json!("11".repeat(32))),
        (6, serde_json::json!([999, "22".repeat(32)])),
        (7, serde_json::json!([999, "33".repeat(32)])),
        (8, serde_json::json!("44".repeat(32))),
        (9, serde_json::json!("55".repeat(32))),
        (10, serde_json::json!("66".repeat(32))),
        (11, serde_json::json!("77".repeat(32))),
        (12, serde_json::json!("88".repeat(32))),
    ];
    let valid = envelope(proof(&association, &admin));
    let mut invalid = attacks
        .into_iter()
        .map(|(index, value)| {
            let mut changed = association.clone();
            changed[index] = value;
            (index.to_string(), envelope(proof(&changed, &admin)))
        })
        .collect::<Vec<_>>();
    let mallory = MlsSessionCrypto::new("Mallory").unwrap();
    invalid.push((
        "actual full issuer key".into(),
        envelope(proof(&association, &mallory)),
    ));
    for (field, payload) in invalid {
        assert!(
            session.handle_control(payload, None).is_err(),
            "accepted changed association {field}"
        );
        assert!(!session.joined && session.pending_join_package.is_some());
        assert!(fixture
            .store
            .get_group_mls_snapshot(&fixture.id)
            .unwrap()
            .is_none());
    }
    session.handle_control(valid, None).unwrap();
    assert!(session.joined);
    assert_eq!(session.crypto.member_count(), 2);
}
