use super::*;

#[test]
fn parses_bundle_uri() {
    let parsed = ParsedOrgBundle::parse(&bundle("orgmesh-1")).unwrap();
    assert_eq!(parsed.mesh_id, "orgmesh-1");
    assert_eq!(parsed.org_name, "acme");
    assert_eq!(parsed.org_pubkey, ORG_KEY_HEX);
}

#[test]
fn rejects_bad_bundles() {
    for bad in [
        "mosh://org?mesh=m&name=x#org=zz",
        &format!("mosh://org?name=x#org={ORG_KEY_HEX}"),
        &format!("mosh://org?mesh=m#org={ORG_KEY_HEX}"),
        &format!("https://org?mesh=m&name=x#org={ORG_KEY_HEX}"),
        "mosh://org?mesh=m&name=x",
        &format!("mosh://org?mesh=m&name=x#{ORG_KEY_HEX}"),
    ] {
        assert!(ParsedOrgBundle::parse(bad).is_err(), "accepted: {bad}");
    }
}

#[test]
fn join_persists_record_and_reports_confirmation_code() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let seed = [42u8; 32];
    let (persistence, path) = temp_persistence("join", seed);
    let moss = Arc::new(MossFfiRuntime::load_default().expect("moss should load"));
    let mut runtime = OrgRuntime::from_shared(Arc::clone(&moss), Some(persistence.clone()));

    let snapshot = runtime
        .join_org(JoinOrgRequest {
            bundle_uri: bundle("orgmesh-join"),
            display_name: "Alice".into(),
            listen_port: 42310,
            static_peer: None,
        })
        .expect("join should succeed");

    let expected_peer = org_signing::peer_id_hex(&SigningKey::from_bytes(&seed));
    assert_eq!(snapshot.own_peer_id, expected_peer);
    assert_eq!(
        snapshot.confirmation_code,
        org_signing::confirmation_code(&expected_peer)
    );
    assert!(!snapshot.in_roster);
    assert!(snapshot.members.is_empty());
    assert!(persistence.get_org_record(ORG_KEY_HEX).unwrap().is_some());

    // Same org twice = duplicate.
    assert!(matches!(
        runtime.join_org(JoinOrgRequest {
            bundle_uri: bundle("orgmesh-join"),
            display_name: "Alice".into(),
            listen_port: 42311,
            static_peer: None,
        }),
        Err(OrgError::Duplicate(_))
    ));

    runtime.leave_org(ORG_KEY_HEX).expect("leave should work");
    assert!(persistence.get_org_record(ORG_KEY_HEX).unwrap().is_none());
    assert!(matches!(
        runtime.poll(ORG_KEY_HEX),
        Err(OrgError::NotJoined(_))
    ));

    let _ = std::fs::remove_file(&path);
}

#[test]
fn rehydrate_restores_sessions_from_records() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let (persistence, path) = temp_persistence("rehydrate", [43u8; 32]);
    let moss = Arc::new(MossFfiRuntime::load_default().expect("moss should load"));
    {
        let mut runtime = OrgRuntime::from_shared(Arc::clone(&moss), Some(persistence.clone()));
        runtime
            .join_org(JoinOrgRequest {
                bundle_uri: bundle("orgmesh-re"),
                display_name: "Alice".into(),
                listen_port: 42320,
                static_peer: None,
            })
            .expect("join should succeed");
    }

    let mut revived = OrgRuntime::from_shared(moss, Some(persistence));
    revived.rehydrate();
    let listing = revived.list();
    assert_eq!(listing.len(), 1);
    assert_eq!(listing[0].org_pubkey, ORG_KEY_HEX);
    assert_eq!(listing[0].org_name, "acme");

    let _ = std::fs::remove_file(&path);
}

#[test]
fn roster_gossip_verifies_persists_and_tracks_removals() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let seed = [44u8; 32];
    let own_peer = org_signing::peer_id_hex(&SigningKey::from_bytes(&seed));
    let other_peer = hex::encode([0x55u8; 32]);
    let (persistence, path) = temp_persistence("roster", seed);
    let moss = Arc::new(MossFfiRuntime::load_default().expect("moss should load"));
    let mut runtime = OrgRuntime::from_shared(moss, Some(persistence.clone()));
    let org = org_key_hex();
    runtime
        .join_org(JoinOrgRequest {
            bundle_uri: org_bundle("orgmesh-roster"),
            display_name: "Alice".into(),
            listen_port: 42330,
            static_peer: None,
        })
        .unwrap();

    // Verified roster lands: members visible, self recognized, persisted.
    let v2 = signed_roster(
        2,
        &[
            (own_peer.as_str(), "alice", "admin"),
            (other_peer.as_str(), "bob", "member"),
        ],
    );
    runtime.ingest_for_test(&org, &roster_wire(&v2));
    let snap = runtime.poll(&org).unwrap();
    assert!(snap.in_roster);
    assert_eq!(snap.roster_version, Some(2));
    assert_eq!(snap.members.len(), 2);
    assert!(snap.members.iter().any(|m| m.is_self));
    assert_eq!(persistence.get_org_roster(&org).unwrap().unwrap(), v2);

    // Rollback rejected, tamper rejected.
    let v1 = signed_roster(1, &[(own_peer.as_str(), "alice", "admin")]);
    runtime.ingest_for_test(&org, &roster_wire(&v1));
    let mut tampered = signed_roster(3, &[(other_peer.as_str(), "eve", "admin")]);
    let byte = tampered.len() / 2;
    tampered[byte] ^= 0x01;
    runtime.ingest_for_test(&org, &roster_wire(&tampered));
    let snap = runtime.poll(&org).unwrap();
    assert_eq!(snap.roster_version, Some(2));

    // Removal shrinks the member list; the crypto kick is driven by the
    // group runtime reconciling against this persisted roster.
    let v3 = signed_roster(3, &[(own_peer.as_str(), "alice", "admin")]);
    runtime.ingest_for_test(&org, &roster_wire(&v3));
    let snap = runtime.poll(&org).unwrap();
    assert_eq!(snap.members.len(), 1);
    assert!(!snap.members.iter().any(|m| m.moss_peer_id == other_peer));
    assert_eq!(
        persistence.get_org_roster(&org).unwrap().unwrap(),
        v3,
        "reconciliation source of truth must be persisted"
    );

    let _ = std::fs::remove_file(&path);
}

#[test]
fn hello_and_stale_roster_trigger_republish() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let seed = [45u8; 32];
    let own_peer = org_signing::peer_id_hex(&SigningKey::from_bytes(&seed));
    let (persistence, path) = temp_persistence("serve", seed);
    let moss = Arc::new(MossFfiRuntime::load_default().expect("moss should load"));
    let mut runtime = OrgRuntime::from_shared(moss, Some(persistence));
    let org = org_key_hex();
    runtime
        .join_org(JoinOrgRequest {
            bundle_uri: org_bundle("orgmesh-serve"),
            display_name: "Alice".into(),
            listen_port: 42340,
            static_peer: None,
        })
        .unwrap();
    let v2 = signed_roster(2, &[(own_peer.as_str(), "alice", "admin")]);
    runtime.ingest_for_test(&org, &roster_wire(&v2));

    // A newcomer's (envelope-valid) hello makes the member serve the roster.
    let newcomer = SigningKey::from_bytes(&[46u8; 32]);
    let hello = OrgMessage::Hello {
        moss_peer_id: org_signing::peer_id_hex(&newcomer),
        display_name: "Bob".into(),
    };
    let mesh = "orgmesh-serve".to_string();
    let ctx = OrgContext {
        org_pubkey: &org,
        mesh_id: &mesh,
        channel_kind: ORG_CHANNEL_KIND,
    };
    let env = org_envelope::sign(&newcomer, &ctx, &serde_json::to_vec(&hello).unwrap());
    let wire = serde_json::to_vec(&OrgWire::Signed {
        payload_b64: encode(&env.payload),
        peer_id: env.peer_id.clone(),
        sig_b64: encode(&env.sig),
    })
    .unwrap();
    runtime.ingest_for_test(&org, &wire);
    assert_eq!(runtime.orgs.get(&org).unwrap().roster_publishes, 1);

    // A hello with a broken signature must NOT be served.
    let mut bad = wire.clone();
    let flip = bad.len() / 2;
    bad[flip] ^= 0x01;
    runtime.ingest_for_test(&org, &bad);
    assert_eq!(runtime.orgs.get(&org).unwrap().roster_publishes, 1);

    // A STALE roster from a lagging peer triggers convergence republish;
    // an equal-version duplicate stays silent.
    let v1 = signed_roster(1, &[(own_peer.as_str(), "alice", "admin")]);
    runtime.ingest_for_test(&org, &roster_wire(&v1));
    assert_eq!(runtime.orgs.get(&org).unwrap().roster_publishes, 2);
    runtime.ingest_for_test(&org, &roster_wire(&v2));
    assert_eq!(runtime.orgs.get(&org).unwrap().roster_publishes, 2);

    let _ = std::fs::remove_file(&path);
}
