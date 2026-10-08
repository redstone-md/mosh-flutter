use super::*;

#[test]
fn sending_an_attachment_saves_its_manifest_before_returning() {
    let db = rehydrate_db("attachment-send");
    let persistence = Arc::new(Persistence::open_with_dek(&db, [9u8; 32]).expect("store"));
    let net = MemoryNet::new();
    net.link_both(ALICE_ID, BOB_ID, PeerTransport::Direct);
    let mut alice = PrivateDmRuntime::with_transport(
        net.endpoint(ALICE_ID),
        temp_store(),
        Some(Arc::clone(&persistence)),
    );
    let mut bob = runtime_on(&net, BOB_ID);
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);

    let sent = alice
        .send_attachment(
            &invite.session_id,
            "clip.bin".to_string(),
            "application/octet-stream".to_string(),
            vec![7; 4096],
            None,
            None,
        )
        .expect("send");
    let rows = persistence
        .list_history_messages(DM_HISTORY, &invite.session_id)
        .expect("history");
    assert!(rows.iter().any(|row| {
        serde_json::from_slice::<crate::conversation::history::StoredMessage<ChatMessage>>(row)
            .ok()
            .and_then(|stored| stored.attachment_manifest)
            .is_some_and(|manifest| manifest.attachment_id == sent.attachment_id)
    }));
}

#[test]
fn accept_writes_no_row_until_the_welcome_lands() {
    let db = rehydrate_db("bob-no-row");
    let persistence =
        Arc::new(Persistence::open_with_dek(&db, [9u8; 32]).expect("store should open"));

    let net = MemoryNet::new();
    net.link_both(ALICE_ID, BOB_ID, PeerTransport::Direct);
    let mut alice = runtime_on(&net, ALICE_ID);
    // Only Bob's runtime owns rows in this store: rows are keyed by session
    // id, so two peers sharing one store would overwrite each other.
    let mut bob = PrivateDmRuntime::with_transport(
        net.endpoint(BOB_ID),
        temp_store(),
        Some(persistence.clone()),
    );

    let invite = invite(&mut alice);
    accept(&mut bob, &invite);

    assert!(
        stored_session_rows(&persistence).is_empty(),
        "a joiner record must not be on disk before its Welcome"
    );

    // The Welcome lands and the next tick persists record + snapshot together.
    connect(&mut alice, &mut bob, &invite.session_id);
    bob.tick(now_ms());

    let rows = stored_session_rows(&persistence);
    assert_eq!(rows.len(), 1, "the Welcome makes the record final");
    assert!(
        !rows[0].group_id.is_empty(),
        "the record carries the joined MLS group"
    );
    assert!(
        persistence
            .get_mls_snapshot(&invite.session_id)
            .expect("snapshot read should pass")
            .is_some(),
        "the snapshot goes down with the record"
    );
    let _ = std::fs::remove_file(&db);
}

#[test]
fn a_joiner_record_without_snapshot_is_dropped_at_rehydrate() {
    let db = rehydrate_db("bob-placeholder");
    let persistence =
        Arc::new(Persistence::open_with_dek(&db, [10u8; 32]).expect("store should open"));

    let (net, mut alice, bob_persistenceless) = memory_pair();
    let _ = bob_persistenceless;
    let mut bob = PrivateDmRuntime::with_transport(
        net.endpoint(BOB_ID),
        temp_store(),
        Some(persistence.clone()),
    );
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    // The legacy behavior: a joiner placeholder record written at accept
    // time, with no snapshot behind it and no Welcome ever coming.
    bob.sessions
        .persist_record(&invite.session_id, false)
        .unwrap();
    assert_eq!(
        stored_session_rows(&persistence).len(),
        1,
        "the placeholder is on disk, as it used to be"
    );

    // The restart: rehydrate sees a joiner record it can never rebuild and
    // deletes the dead row instead of warning about it at every startup.
    let mut revived = PrivateDmRuntime::with_transport(
        net.endpoint(BOB_ID),
        temp_store(),
        Some(persistence.clone()),
    );
    revived.rehydrate();
    assert!(
        revived
            .list_sessions()
            .expect("listing should pass")
            .sessions
            .is_empty(),
        "a placeholder never rebuilt a session"
    );
    assert!(
        stored_session_rows(&persistence).is_empty(),
        "the dead row is deleted, not kept as a per-startup warning"
    );
    let _ = std::fs::remove_file(&db);
}

#[test]
fn a_final_record_without_snapshot_is_kept_and_reported() {
    let db = rehydrate_db("final-no-snapshot");
    let persistence =
        Arc::new(Persistence::open_with_dek(&db, [11u8; 32]).expect("store should open"));

    // A final (group_id present) record written without its snapshot: the
    // state a silently failed snapshot write leaves behind.
    let record = contracts::PersistedSession {
        invitation: None,
        membership: None,
        role_is_alice: true,
        display_name: "Alice".to_string(),
        participant_id: "participant-1".to_string(),
        session_id: "session-finalish".to_string(),
        mesh_id: "mesh-finalish".to_string(),
        fingerprint: "FP".to_string(),
        invite_uri: None,
        signer_public: vec![1, 2, 3],
        group_id: vec![9u8; 16],
        listen_port: 0,
        static_peer: None,
        peer_moss_id: None,
        read_message_ids: vec![],
    };
    crate::conversation::history::History::new(DM_HISTORY)
        .write_record(&persistence, "session-finalish", &record)
        .unwrap();
    assert_eq!(stored_session_rows(&persistence).len(), 1);

    let net = MemoryNet::new();
    let mut revived = PrivateDmRuntime::with_transport(
        net.endpoint(ALICE_ID),
        temp_store(),
        Some(persistence.clone()),
    );
    revived.rehydrate();
    assert!(
        revived
            .list_sessions()
            .expect("listing should pass")
            .sessions
            .is_empty(),
        "a record without its snapshot is skipped, not rebuilt"
    );
    assert_eq!(
        stored_session_rows(&persistence).len(),
        1,
        "the corrupt row stays on disk: its history rows remain recoverable"
    );
    let _ = std::fs::remove_file(&db);
}
