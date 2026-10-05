use super::*;
use crate::sender_auth::SenderProof;
use crate::test_temp_directory::TempDirectory;

fn admit(runtime: &mut PrivateGroupRuntime, id: &str, name: &str) -> MlsSessionCrypto {
    let mut member = MlsSessionCrypto::new(name).unwrap();
    let package = member.key_package_bytes().unwrap();
    let outcome = runtime
        .groups
        .get_mut(id)
        .unwrap()
        .crypto
        .add_members(&[&package])
        .unwrap();
    member
        .join_welcome(&outcome.welcome_bytes, &outcome.tree_bytes)
        .unwrap();
    member
}

fn frame(session: &GroupSession, member: &mut MlsSessionCrypto, identity: &SigningKey) -> Vec<u8> {
    let envelope = DataEnvelope {
        origin: None,
        group_id: session.group_id.clone(),
        participant_id: "org member".into(),
        from_device: "Bob".into(),
        from_fingerprint: org_signing::peer_id_hex(identity),
        message_id: Some("org-authenticated-text".into()),
        sent_at_ms: Some(42),
        ciphertext_b64: encode(&member.encrypt(b"org text").unwrap()),
    };
    let proof = SenderProof::sign(
        identity,
        member,
        &OrgContext {
            org_pubkey: session.org_pubkey.as_deref().unwrap(),
            mesh_id: &session.mesh_id,
            channel_kind: &session.data_channel,
        },
        serde_json::to_vec(&envelope).unwrap(),
    )
    .unwrap();
    serde_json::to_vec(&proof).unwrap()
}

#[test]
fn org_authentication_requires_both_the_roster_and_the_moss_bound_leaf_credential() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let directory = TempDirectory::new("mosh-org-authentication");
    let store = Arc::new(
        Persistence::open_with_dek(&directory.path().join("history.redb"), [25; 32]).unwrap(),
    );
    store.put_moss_identity(&identity_blob([4; 32])).unwrap();
    let _identity = crate::moss_ffi::replace_test_keystore(Some(store.clone()));
    let peer = SigningKey::from_bytes(&[6; 32]);
    let owner = org_signing::peer_id_hex(&SigningKey::from_bytes(&[4; 32]));
    let peer_id = org_signing::peer_id_hex(&peer);
    put_signed_roster(&store, &[(&owner, "admin"), (&peer_id, "member")]);
    let moss = Arc::new(MossFfiRuntime::load_default().unwrap());
    let mut runtime = PrivateGroupRuntime::from_shared(
        moss,
        Arc::new(AttachmentStore::new(directory.path()).unwrap()),
        Some(store.clone()),
    );
    let id = runtime
        .create_group(CreateGroupRequest {
            label: None,
            display_name: "Alice".into(),
            listen_port: 0,
            static_peer: None,
            org_pubkey: Some(org_key_hex()),
        })
        .unwrap()
        .group_id;
    let mut member = admit(&mut runtime, &id, &peer_id);
    let genuine = frame(runtime.groups.get(&id).unwrap(), &mut member, &peer);
    runtime
        .groups
        .get_mut(&id)
        .unwrap()
        .handle_data(genuine)
        .unwrap();
    assert_eq!(
        runtime.poll(&id).unwrap().messages[0].from_fingerprint,
        peer_id
    );
    let blocked = frame(runtime.groups.get(&id).unwrap(), &mut member, &peer);
    put_signed_roster(&store, &[(&owner, "admin")]);
    assert!(runtime
        .groups
        .get_mut(&id)
        .unwrap()
        .handle_data(blocked.clone())
        .is_err());
    put_signed_roster(&store, &[(&owner, "admin"), (&peer_id, "member")]);
    runtime
        .groups
        .get_mut(&id)
        .unwrap()
        .handle_data(blocked)
        .unwrap();
    let mut wrong_credential = admit(&mut runtime, &id, "self-claimed name");
    let invalid = frame(
        runtime.groups.get(&id).unwrap(),
        &mut wrong_credential,
        &peer,
    );
    assert!(runtime
        .groups
        .get_mut(&id)
        .unwrap()
        .handle_data(invalid)
        .is_err());
}
