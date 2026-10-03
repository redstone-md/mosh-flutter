use super::*;

#[test]
fn sequence_commit_handles_out_of_order_duplicates_and_logs() {
    let mut db_path: PathBuf = std::env::temp_dir();
    db_path.push(format!("mosh-seq-commit-{}.redb", std::process::id()));
    let _ = std::fs::remove_file(&db_path);
    let p = Persistence::open_with_dek(&db_path, [17u8; 32]).expect("store should open");

    // Admin + member, crypto only — no moss node involved.
    let mut admin = MlsSessionCrypto::new("admin").unwrap();
    admin.create_group().unwrap();
    let mut member = MlsSessionCrypto::new("member").unwrap();
    let kp = member.key_package_bytes().unwrap();
    let (welcome, tree) = admin.add_peer(&kp).unwrap();
    member.join_welcome(&welcome, &tree).unwrap();

    // Two successive membership commits the member has not seen yet.
    let mut dave = MlsSessionCrypto::new("dave").unwrap();
    let kp_d = dave.key_package_bytes().unwrap();
    let c1 = admin.add_members(&[kp_d.as_slice()]).unwrap();
    let mut erin = MlsSessionCrypto::new("erin").unwrap();
    let kp_e = erin.key_package_bytes().unwrap();
    let c2 = admin.add_members(&[kp_e.as_slice()]).unwrap();
    let c1_b64 = encode(&c1.commit_bytes);
    let c2_b64 = encode(&c2.commit_bytes);

    let mut seq = CommitSequencer::new();
    // Reordered delivery: the later commit first -> buffered + gap.
    let out = sequence_commit(&mut member, &mut seq, Some(&p), "g-seq", &c2_b64).unwrap();
    assert_eq!(out, SequenceOutcome::Gapped);
    assert_eq!(member.member_count(), 2, "future commit must not apply");
    // The missing commit arrives -> both apply, in order.
    let out = sequence_commit(&mut member, &mut seq, Some(&p), "g-seq", &c1_b64).unwrap();
    assert_eq!(out, SequenceOutcome::Done);
    assert_eq!(member.member_count(), 4);
    // Duplicate re-delivery is a no-op.
    let out = sequence_commit(&mut member, &mut seq, Some(&p), "g-seq", &c1_b64).unwrap();
    assert_eq!(out, SequenceOutcome::Done);
    assert_eq!(member.member_count(), 4);
    // Both applied commits landed in the log, ascending by epoch.
    let logged = p.list_group_commits_from("g-seq", 0).unwrap();
    assert_eq!(logged.len(), 2);
    assert!(logged[0].0 < logged[1].0);

    let _ = std::fs::remove_file(&db_path);
}

#[test]
fn resync_replay_bridges_gap_and_clears_rejoin() {
    // Member buffered a future commit; the admin's replay bridges it.
    let mut admin = MlsSessionCrypto::new("admin").unwrap();
    admin.create_group().unwrap();
    let mut member = MlsSessionCrypto::new("member").unwrap();
    let kp = member.key_package_bytes().unwrap();
    let (welcome, tree) = admin.add_peer(&kp).unwrap();
    member.join_welcome(&welcome, &tree).unwrap();

    let mut dave = MlsSessionCrypto::new("dave").unwrap();
    let kp_d = dave.key_package_bytes().unwrap();
    let c1 = admin.add_members(&[kp_d.as_slice()]).unwrap();
    let mut erin = MlsSessionCrypto::new("erin").unwrap();
    let kp_e = erin.key_package_bytes().unwrap();
    let c2 = admin.add_members(&[kp_e.as_slice()]).unwrap();

    let mut seq = CommitSequencer::new();
    // Only the later commit arrived -> gap.
    let out = sequence_commit(
        &mut member,
        &mut seq,
        None,
        "g-rs",
        &encode(&c2.commit_bytes),
    )
    .unwrap();
    assert_eq!(out, SequenceOutcome::Gapped);

    // Admin replay carries the missing commit (and a duplicate).
    let replay = vec![
        ResyncCommit {
            epoch: 0,
            commit_b64: encode(&c1.commit_bytes),
        },
        ResyncCommit {
            epoch: 0,
            commit_b64: encode(&c2.commit_bytes),
        },
    ];
    let needs_rejoin = absorb_resync_commits(&mut member, &mut seq, None, "g-rs", replay);
    assert!(!needs_rejoin);
    assert_eq!(member.member_count(), 4);
}

#[test]
fn empty_resync_replay_flags_rejoin() {
    let mut admin = MlsSessionCrypto::new("admin").unwrap();
    admin.create_group().unwrap();
    let mut member = MlsSessionCrypto::new("member").unwrap();
    let kp = member.key_package_bytes().unwrap();
    let (welcome, tree) = admin.add_peer(&kp).unwrap();
    member.join_welcome(&welcome, &tree).unwrap();

    let mut dave = MlsSessionCrypto::new("dave").unwrap();
    let kp_d = dave.key_package_bytes().unwrap();
    let _c1 = admin.add_members(&[kp_d.as_slice()]).unwrap();
    let mut erin = MlsSessionCrypto::new("erin").unwrap();
    let kp_e = erin.key_package_bytes().unwrap();
    let c2 = admin.add_members(&[kp_e.as_slice()]).unwrap();

    let mut seq = CommitSequencer::new();
    sequence_commit(
        &mut member,
        &mut seq,
        None,
        "g-rj",
        &encode(&c2.commit_bytes),
    )
    .unwrap();
    // Admin has nothing to replay (fresh state) -> member must rejoin.
    let needs_rejoin = absorb_resync_commits(&mut member, &mut seq, None, "g-rj", Vec::new());
    assert!(needs_rejoin);
}

#[test]
fn org_admission_enforces_identity_and_roster_with_replace_dedup() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut db_path: PathBuf = std::env::temp_dir();
    db_path.push(format!("mosh-org-group-{}.redb", std::process::id()));
    let _ = std::fs::remove_file(&db_path);
    let persistence =
        Arc::new(Persistence::open_with_dek(&db_path, [23u8; 32]).expect("store should open"));

    let admin_seed = [71u8; 32];
    persistence
        .put_moss_identity(&identity_blob(admin_seed))
        .unwrap();
    let admin_peer = org_signing::peer_id_hex(&SigningKey::from_bytes(&admin_seed));
    let member_key = SigningKey::from_bytes(&[72u8; 32]);
    let member_peer = org_signing::peer_id_hex(&member_key);
    let stranger_key = SigningKey::from_bytes(&[73u8; 32]);
    put_signed_roster(
        &persistence,
        &[
            (admin_peer.as_str(), "admin"),
            (member_peer.as_str(), "member"),
        ],
    );

    let moss = Arc::new(MossFfiRuntime::load_default().expect("moss should load"));
    let mut runtime =
        PrivateGroupRuntime::from_shared(moss, temp_store(), Some(persistence.clone()));
    let created = runtime
        .create_group(CreateGroupRequest {
            label: Some("Org Group".to_string()),
            display_name: "Alice".to_string(),
            listen_port: 42360,
            static_peer: None,
            org_pubkey: Some(org_key_hex()),
        })
        .expect("org group should be created");

    // ADR 0004: the creator's leaf credential is their peer-id.
    {
        let session = runtime.groups.get(&created.group_id).unwrap();
        assert_eq!(session.crypto.member_identities(), vec![admin_peer.clone()]);
    }
    let (control_channel, mesh_id) = {
        let s = runtime.groups.get(&created.group_id).unwrap();
        (s.control_channel.clone(), s.mesh_id.clone())
    };
    let key_package_env = |identity: &str, participant: &str| {
        let mut crypto = MlsSessionCrypto::new(identity).unwrap();
        ControlEnvelope::KeyPackage {
            group_id: created.group_id.clone(),
            participant_id: participant.to_string(),
            from_device: "peer".to_string(),
            from_fingerprint: "fp".to_string(),
            key_package_b64: encode(&crypto.key_package_bytes().unwrap()),
        }
    };
    let deliver = |runtime: &mut PrivateGroupRuntime, payload: Vec<u8>| {
        let session = runtime.groups.get_mut(&created.group_id).unwrap();
        let _ = session.handle_moss_message(MossReceivedMessage {
            channel: control_channel.clone(),
            payload,
        });
    };

    // Roster member with matching credential: admitted.
    let env = key_package_env(&member_peer, "p-bob");
    deliver(
        &mut runtime,
        org_signed_control(&member_key, &control_channel, &mesh_id, &env),
    );
    {
        let session = runtime.groups.get(&created.group_id).unwrap();
        assert_eq!(
            session.crypto.member_count(),
            2,
            "member should be admitted"
        );
    }

    // Stranger (valid envelope, not in roster): dropped.
    let stranger_peer = org_signing::peer_id_hex(&stranger_key);
    let env = key_package_env(&stranger_peer, "p-eve");
    deliver(
        &mut runtime,
        org_signed_control(&stranger_key, &control_channel, &mesh_id, &env),
    );
    // Credential != envelope sender (member relays someone else's kp): dropped.
    let env = key_package_env(&stranger_peer, "p-eve2");
    deliver(
        &mut runtime,
        org_signed_control(&member_key, &control_channel, &mesh_id, &env),
    );
    // Raw, unenveloped frame on an org control channel: dropped.
    let env = key_package_env(&member_peer, "p-raw");
    deliver(&mut runtime, serde_json::to_vec(&env).unwrap());
    {
        let session = runtime.groups.get(&created.group_id).unwrap();
        assert_eq!(
            session.crypto.member_count(),
            2,
            "rejections must not admit"
        );
    }

    // Rejoin with a FRESH key package (device reinstall): replace, not add.
    let env = key_package_env(&member_peer, "p-bob-2");
    deliver(
        &mut runtime,
        org_signed_control(&member_key, &control_channel, &mesh_id, &env),
    );
    {
        let session = runtime.groups.get_mut(&created.group_id).unwrap();
        assert_eq!(
            session.crypto.member_count(),
            2,
            "stale leaf must be replaced in the same commit"
        );
        let snapshot = session.snapshot();
        assert_eq!(snapshot.org_pubkey.as_deref(), Some(org_key_hex().as_str()));
        assert_eq!(snapshot.member_peer_ids.len(), 2);
    }

    let _ = std::fs::remove_file(&db_path);
}
