use super::*;

#[test]
fn group_history_and_session_survive_restart() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut db_path: PathBuf = std::env::temp_dir();
    db_path.push(format!("mosh-group-rehydrate-{}.redb", std::process::id()));
    let _ = std::fs::remove_file(&db_path);

    let persistence =
        Arc::new(Persistence::open_with_dek(&db_path, [13u8; 32]).expect("store should open"));
    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));

    let group_id = {
        let mut groups = PrivateGroupRuntime::from_shared(
            Arc::clone(&runtime),
            temp_store(),
            Some(persistence.clone()),
        );
        let created = groups
            .create_group(CreateGroupRequest {
                label: Some("Restart Club".to_string()),
                display_name: "Alice".to_string(),
                listen_port: 42240,
                static_peer: None,
                org_pubkey: None,
            })
            .expect("group should be created");
        groups
            .send(&created.group_id, "hello after group restart".to_string())
            .expect("group message should send");
        created.group_id
    };

    let mut revived = PrivateGroupRuntime::from_shared(
        Arc::clone(&runtime),
        temp_store(),
        Some(persistence.clone()),
    );
    revived.rehydrate();

    let listing = revived.list().expect("listing should pass");
    let group = listing
        .groups
        .iter()
        .find(|group| group.group_id == group_id)
        .expect("rehydrated group should be present");
    assert_eq!(group.label.as_deref(), Some("Restart Club"));
    assert!(
        group
            .messages
            .iter()
            .any(|message| message.body == "hello after group restart"),
        "rehydrated group message missing: {:?}",
        group.messages
    );

    let listing2 = revived.list().expect("second listing should pass");
    let group2 = listing2
        .groups
        .iter()
        .find(|group| group.group_id == group_id)
        .expect("group should still be present");
    let matching = group2
        .messages
        .iter()
        .filter(|message| message.body == "hello after group restart")
        .count();
    assert_eq!(matching, 1, "persist tail duplicated the group message");

    let _ = std::fs::remove_file(&db_path);
}

#[test]
fn a_group_joiner_record_without_snapshot_is_dropped_at_rehydrate() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let db_path = rehydrate_db("orphan");
    let persistence =
        Arc::new(Persistence::open_with_dek(&db_path, [31u8; 32]).expect("store should open"));

    // A joiner placeholder the way an interrupted invite could leave it:
    // not joined, no MLS group, no snapshot behind the record.
    let record = PersistedGroupSession {
        group_id: "group-orphan".to_string(),
        mesh_id: "mesh-orphan".to_string(),
        label: None,
        display_name: "Bob".to_string(),
        participant_id: "participant-1".to_string(),
        device_fingerprint: "FP".to_string(),
        creator_fingerprint: "ADMIN-FP".to_string(),
        current_admin_fingerprint: "ADMIN-FP".to_string(),
        is_admin: false,
        invite_uri: None,
        joined: false,
        signer_public: vec![1, 2, 3],
        mls_group_id: vec![],
        listen_port: 0,
        static_peer: None,
        org_pubkey: None,
        names: Default::default(),
    };
    crate::conversation::history::History::new(GROUP_HISTORY)
        .write_record(&persistence, "group-orphan", &record)
        .unwrap();
    assert_eq!(
        persisted_group_rows(&persistence).len(),
        1,
        "the placeholder is on disk"
    );

    let moss = Arc::new(MossFfiRuntime::load_default().expect("moss should load"));
    let mut runtime =
        PrivateGroupRuntime::from_shared(moss, temp_store(), Some(persistence.clone()));
    runtime.rehydrate();

    assert!(
        persisted_group_rows(&persistence).is_empty(),
        "a group record that can never rebuild is deleted, not kept as a warning"
    );
    let _ = std::fs::remove_file(&db_path);
}

#[test]
fn a_real_group_record_without_snapshot_is_kept_and_reported() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let db_path = rehydrate_db("corrupt");
    let persistence =
        Arc::new(Persistence::open_with_dek(&db_path, [32u8; 32]).expect("store should open"));

    // A record that claims a real MLS group but lost its snapshot: the
    // state a silently failed snapshot write leaves behind.
    let record = PersistedGroupSession {
        group_id: "group-corrupt".to_string(),
        mesh_id: "mesh-corrupt".to_string(),
        label: None,
        display_name: "Alice".to_string(),
        participant_id: "participant-1".to_string(),
        device_fingerprint: "FP".to_string(),
        creator_fingerprint: "FP".to_string(),
        current_admin_fingerprint: "FP".to_string(),
        is_admin: true,
        invite_uri: None,
        joined: true,
        signer_public: vec![1, 2, 3],
        mls_group_id: vec![9u8; 16],
        listen_port: 0,
        static_peer: None,
        org_pubkey: None,
        names: Default::default(),
    };
    crate::conversation::history::History::new(GROUP_HISTORY)
        .write_record(&persistence, "group-corrupt", &record)
        .unwrap();
    assert_eq!(persisted_group_rows(&persistence).len(), 1);

    let moss = Arc::new(MossFfiRuntime::load_default().expect("moss should load"));
    let mut runtime =
        PrivateGroupRuntime::from_shared(moss, temp_store(), Some(persistence.clone()));
    runtime.rehydrate();

    assert_eq!(
        persisted_group_rows(&persistence).len(),
        1,
        "a real record missing its snapshot stays recoverable on disk"
    );
    let _ = std::fs::remove_file(&db_path);
}
