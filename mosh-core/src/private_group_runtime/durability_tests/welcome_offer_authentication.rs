use super::*;

#[test]
fn a_claimed_admin_cannot_replace_the_groups_invitation_key_with_its_own_welcome() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::empty();
    let mut genuine = MlsSessionCrypto::new("Alice").unwrap();
    genuine.create_group().unwrap();
    let invite = build_invite_uri(
        "welcome-auth-mesh",
        "welcome-auth-group",
        &genuine.fingerprint(),
        &None,
    );
    fixture.join(&invite, "Bob");
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    let package = session.crypto.key_package_bytes().unwrap();
    let mut attacker = MlsSessionCrypto::new("Mallory").unwrap();
    attacker.create_group().unwrap();
    let wrong = attacker.add_members(&[&package]).unwrap();
    let envelope = ControlEnvelope::Welcome {
        group_id: fixture.id.clone(),
        for_participant_id: session.participant_id.clone(),
        from_fingerprint: genuine.fingerprint(),
        welcome_b64: encode(&wrong.welcome_bytes),
        tree_b64: encode(&wrong.tree_bytes),
        commit_b64: encode(&wrong.commit_bytes),
    };
    assert!(session
        .handle_control(serde_json::to_vec(&envelope).unwrap(), None)
        .is_err());
    assert!(!session.joined);
    assert!(session.pending_join_package.is_some());
    fixture.deliver_welcome(&mut genuine);
    assert_eq!(fixture.runtime.poll(&fixture.id).unwrap().member_count, 2);
}

fn owned_offer_uri(session: &GroupSession, target: &str) -> String {
    let mut dm = MlsSessionCrypto::new("Alice DM").unwrap();
    dm.create_group().unwrap();
    let raw = format!(
        "mosh://invite?mesh=offer-auth-mesh&session=offer-auth-session&moss={}#fp={}",
        session.device_fingerprint,
        dm.fingerprint(),
    );
    let mut url = url::Url::parse(&raw).unwrap();
    url.query_pairs_mut().append_pair("target", target);
    crate::private_dm_runtime::invite_ownership::sign_invite(
        url.as_str(),
        session.node.identity_signer().unwrap(),
        &dm,
    )
    .unwrap()
}

#[test]
fn authenticated_org_offers_fit_the_real_moss_publish_limit() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    let uri = owned_offer_uri(session, &"b".repeat(64));
    let offer = DmOffers::mint(
        session.display_name.clone(),
        session.device_fingerprint.clone(),
        "b".repeat(64),
        uri,
    );
    let offer_ciphertext_b64 = session.crypto.encrypt_json(&offer).unwrap();
    let proof = session
        .sign_application(
            &ControlEnvelope::DmOffer {
                group_id: session.group_id.clone(),
                offer_ciphertext_b64,
            },
            &session.control_channel,
        )
        .unwrap();
    let wrapped = org_envelope::sign(
        session.node.identity_signer().unwrap(),
        &OrgContext {
            org_pubkey: &"a".repeat(64),
            mesh_id: &session.mesh_id,
            channel_kind: &session.control_channel,
        },
        &serde_json::to_vec(&proof).unwrap(),
    );
    let payload = serde_json::to_vec(&wrapped).unwrap();
    assert!(
        payload.len() <= 65_536,
        "{} exceeds Moss publish limit",
        payload.len()
    );
}

#[test]
fn dm_offers_checkpoint_the_send_generation_and_storage_refusal_prevents_publication() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let target = "b".repeat(64);
    let uri = owned_offer_uri(fixture.runtime.groups.get(&fixture.id).unwrap(), &target);
    let fault = fixture.store.refuse_group_snapshot_writes();
    let _publication = fail_next_test_publish("deferred offer publication");
    assert!(matches!(
        fixture
            .runtime
            .send_dm_offer(&fixture.id, target.clone(), uri.clone()),
        Err(PrivateGroupError::Persistence(_))
    ));
    drop(fault);
    assert!(matches!(
        fixture.runtime.send_dm_offer(&fixture.id, target, uri),
        Err(PrivateGroupError::Moss(message)) if message.contains("deferred offer publication")
    ));
    let snapshot = fixture
        .store
        .get_group_mls_snapshot(&fixture.id)
        .unwrap()
        .unwrap();
    let saved: std::collections::BTreeMap<Vec<u8>, Vec<u8>> =
        serde_json::from_slice::<Vec<(Vec<u8>, Vec<u8>)>>(&snapshot)
            .unwrap()
            .into_iter()
            .collect();
    let signer = fixture
        .runtime
        .groups
        .get(&fixture.id)
        .unwrap()
        .crypto
        .signer_public();
    fixture.restart();
    let restored: std::collections::BTreeMap<Vec<u8>, Vec<u8>> =
        serde_json::from_slice::<Vec<(Vec<u8>, Vec<u8>)>>(
            &fixture
                .runtime
                .groups
                .get(&fixture.id)
                .unwrap()
                .crypto
                .snapshot(),
        )
        .unwrap()
        .into_iter()
        .collect();
    assert!(
        restored == saved,
        "the offered generation must survive restart"
    );
    assert_eq!(
        fixture
            .runtime
            .groups
            .get(&fixture.id)
            .unwrap()
            .crypto
            .signer_public(),
        signer
    );
}
