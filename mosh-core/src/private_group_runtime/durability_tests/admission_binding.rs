use super::*;

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
