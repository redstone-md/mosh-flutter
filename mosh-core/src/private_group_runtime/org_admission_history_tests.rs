use super::*;

#[test]
fn org_admission_rejects_mismatched_group_epoch_signer_and_wrapper() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let (id, mut admin) = begin(&mut fixture);
    register(&mut fixture, &id);
    let valid = prepare_welcome(&mut fixture, &id, &mut admin);
    let package = fixture
        .groups
        .groups
        .get(&id)
        .unwrap()
        .pending_join_package
        .clone()
        .unwrap();
    let mut foreign = MlsSessionCrypto::new(fixture.own_peer()).unwrap();
    foreign.create_group().unwrap();
    let wrong_group = foreign.add_members(&[&package]).unwrap();
    let later = admin
        .add_members(&[&MlsSessionCrypto::new("Carol")
            .unwrap()
            .key_package_bytes()
            .unwrap()])
        .unwrap();
    for raw in [&wrong_group.commit_bytes, &later.commit_bytes] {
        let frame = changed_fields(&fixture, &id, &valid, &[("commit_b64", encode(raw))]);
        inbox::deliver(frame);
        assert_eq!(fixture.groups.poll(&id).unwrap().member_count, 0);
    }
    inbox::deliver(changed_fields(
        &fixture,
        &id,
        &valid,
        &[
            ("welcome_b64", encode(&wrong_group.welcome_bytes)),
            ("tree_b64", encode(&wrong_group.tree_bytes)),
        ],
    ));
    assert_eq!(fixture.groups.poll(&id).unwrap().member_count, 0);
    inbox::deliver(corrupted_wrapper(&valid));
    assert_eq!(fixture.groups.poll(&id).unwrap().member_count, 0);
    let session = fixture.groups.groups.get(&id).unwrap();
    assert_eq!(session.pending_join_package.as_ref(), Some(&package));
    assert!(fixture.store.get_group_mls_snapshot(&id).unwrap().is_none());
    inbox::deliver(valid);
    assert_eq!(fixture.groups.poll(&id).unwrap().member_count, 2);
}

fn changed_fields(
    fixture: &Fixture,
    id: &str,
    valid: &MossReceivedMessage,
    fields: &[(&str, String)],
) -> MossReceivedMessage {
    let signed: OrgSigned = decode_json(&valid.payload).unwrap();
    let mut payload: serde_json::Value = serde_json::from_slice(&signed.payload).unwrap();
    for (key, value) in fields {
        payload[*key] = serde_json::Value::String(value.clone());
    }
    let session = fixture.groups.groups.get(id).unwrap();
    let signed = org_envelope::sign(
        &SigningKey::from_bytes(&[90; 32]),
        &OrgContext {
            org_pubkey: &fixture.org_key,
            mesh_id: &session.mesh_id,
            channel_kind: &session.control_channel,
        },
        &serde_json::to_vec(&payload).unwrap(),
    );
    MossReceivedMessage {
        channel: valid.channel.clone(),
        payload: serde_json::to_vec(&signed).unwrap(),
    }
}

fn corrupted_wrapper(valid: &MossReceivedMessage) -> MossReceivedMessage {
    let mut corrupt: OrgSigned = decode_json(&valid.payload).unwrap();
    corrupt.sig[0] ^= 1;
    MossReceivedMessage {
        channel: valid.channel.clone(),
        payload: serde_json::to_vec(&corrupt).unwrap(),
    }
}
