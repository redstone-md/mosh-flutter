use super::*;

#[test]
fn dm_offers_are_roster_gated_targeted_and_accept_once() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let seed = [47u8; 32];
    let own_peer = org_signing::peer_id_hex(&SigningKey::from_bytes(&seed));
    let member_key = SigningKey::from_bytes(&[48u8; 32]);
    let member_peer = org_signing::peer_id_hex(&member_key);
    let stranger_key = SigningKey::from_bytes(&[49u8; 32]);
    let (persistence, path) = temp_persistence("dmoffer", seed);
    let moss = Arc::new(MossFfiRuntime::load_default().expect("moss should load"));
    let mut runtime = OrgRuntime::from_shared(moss, Some(persistence.clone()));
    let org = org_key_hex();
    let mesh = "orgmesh-dm";
    runtime
        .join_org(JoinOrgRequest {
            bundle_uri: org_bundle(mesh),
            display_name: "Alice".into(),
            listen_port: 42350,
            static_peer: None,
        })
        .unwrap();
    let roster = signed_roster(
        1,
        &[
            (own_peer.as_str(), "alice", "admin"),
            (member_peer.as_str(), "bob", "member"),
        ],
    );
    runtime.ingest_for_test(&org, &roster_wire(&roster));

    let offer = |id: &str, target: &str| OrgMessage::DmOffer {
        offer_id: id.into(),
        target_peer_id: target.into(),
        from_name: "Bob".into(),
        invite_uri: "mosh://dm?mesh=x&session=y".into(),
    };

    // From a member, to us: surfaces exactly once despite redelivery.
    runtime.ingest_for_test(
        &org,
        &signed_wire(&member_key, mesh, &offer("o1", &own_peer)),
    );
    runtime.ingest_for_test(
        &org,
        &signed_wire(&member_key, mesh, &offer("o1", &own_peer)),
    );
    // From a stranger (envelope valid, not in roster): dropped.
    runtime.ingest_for_test(
        &org,
        &signed_wire(&stranger_key, mesh, &offer("o2", &own_peer)),
    );
    // Aimed at someone else: ignored.
    runtime.ingest_for_test(
        &org,
        &signed_wire(&member_key, mesh, &offer("o3", &member_peer)),
    );

    let snap = runtime.poll(&org).unwrap();
    assert_eq!(snap.dm_offers.len(), 1);
    assert_eq!(snap.dm_offers[0].offer_id, "o1");
    assert_eq!(snap.dm_offers[0].from_peer_id, member_peer);

    // Accept: returns the offer view, records a link, persists it.
    let accepted = runtime.accept_dm_offer(&org, "o1").unwrap();
    assert_eq!(accepted.invite_uri, "mosh://dm?mesh=x&session=y");
    assert_eq!(accepted.from_peer_id, member_peer);
    runtime.link_dm(&org, &member_peer, "session-1").unwrap();
    let snap = runtime.poll(&org).unwrap();
    assert!(snap.dm_offers.is_empty());
    assert_eq!(snap.dm_links.len(), 1);
    assert_eq!(snap.dm_links[0].session_id.as_deref(), Some("session-1"));
    // A replay of the accepted offer does not resurface.
    runtime.ingest_for_test(
        &org,
        &signed_wire(&member_key, mesh, &offer("o1", &own_peer)),
    );
    assert!(runtime.poll(&org).unwrap().dm_offers.is_empty());
    // Link (with its session id) survives a restart via the record.
    let record_bytes = persistence.get_org_record(&org).unwrap().unwrap();
    let record: PersistedOrgRecord = serde_json::from_slice(&record_bytes).unwrap();
    assert_eq!(record.dm_links.len(), 1);
    assert_eq!(record.dm_links[0].session_id.as_deref(), Some("session-1"));

    // Revocation keeps the link (badge data) while future offers drop.
    let v2 = signed_roster(2, &[(own_peer.as_str(), "alice", "admin")]);
    runtime.ingest_for_test(&org, &roster_wire(&v2));
    runtime.ingest_for_test(
        &org,
        &signed_wire(&member_key, mesh, &offer("o4", &own_peer)),
    );
    let snap = runtime.poll(&org).unwrap();
    assert!(snap.dm_offers.is_empty());
    assert_eq!(snap.dm_links.len(), 1);

    let _ = std::fs::remove_file(&path);
}
