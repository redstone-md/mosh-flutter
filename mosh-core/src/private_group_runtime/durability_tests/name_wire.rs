use super::*;

#[test]
fn long_unicode_group_names_fit_the_real_org_transport_limit() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::empty();
    let root = SigningKey::from_bytes(&[61; 32]);
    let org = hex::encode(root.verifying_key().as_bytes());
    names::create_org_group(&mut fixture, &org, &"😎".repeat(64));
    let key = SigningKey::from_bytes(&[17; 32]);
    let mut roster = serde_json::json!({"org_pubkey":org,"org_name":"Org","version":1,
        "members":[{"moss_peer_id":hex::encode(key.verifying_key().as_bytes()),"name":"Alice","role":"admin"}]});
    let signed = org_roster::sign_roster(&mut roster, &root).unwrap();
    fixture.store.put_org_roster(&org, &signed).unwrap();
    fixture
        .runtime
        .rename_group(&fixture.id, &"😎".repeat(64))
        .unwrap();
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    let proof = decode(&session.name_handoff_proof().unwrap().unwrap()).unwrap();
    let packet = org_envelope::sign(
        &key,
        &OrgContext {
            org_pubkey: &org,
            mesh_id: &session.mesh_id,
            channel_kind: &session.control_channel,
        },
        &proof,
    );
    let wire = serde_json::to_vec(&packet).unwrap();
    assert!(
        wire.len() <= 64 * 1024,
        "name frame is {} bytes",
        wire.len()
    );
    session
        .node
        .publish_room(&session.mesh_id, &session.control_channel, &wire)
        .unwrap();
}
