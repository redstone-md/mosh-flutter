use super::*;

/// A promoted admin's commit waits in the roster-lag buffer until the roster
/// that promotes it lands. Nobody else may push it out: not keys outside the
/// group, which any signer can mint, and not another member flooding claims.
#[test]
fn a_flood_of_lagged_claims_cannot_evict_a_promoted_admins_commit() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut db_path: PathBuf = std::env::temp_dir();
    db_path.push(format!("mosh-org-roster-lag-{}.redb", std::process::id()));
    let _ = std::fs::remove_file(&db_path);
    let persistence =
        Arc::new(Persistence::open_with_dek(&db_path, [37u8; 32]).expect("store should open"));
    let _identity = crate::moss_ffi::replace_test_keystore(Some(persistence.clone()));
    let moss = Arc::new(MossFfiRuntime::load_default().expect("moss should load"));
    let native = moss
        .init_default_node("org-roster-lag-identity", &Default::default())
        .unwrap();
    let admin_peer = native.public_key_hex().unwrap();
    drop(native);
    let member_b_key = SigningKey::from_bytes(&[84u8; 32]);
    let member_b = org_signing::peer_id_hex(&member_b_key);
    let member_d_key = SigningKey::from_bytes(&[86u8; 32]);
    let member_d = org_signing::peer_id_hex(&member_d_key);
    let member_c = hex::encode([0x85u8; 32]);
    let member_e = hex::encode([0x87u8; 32]);
    let put_roster = |version: u64, b_role: &str| {
        let mut doc = serde_json::json!({
            "org_pubkey": org_key_hex(),
            "org_name": "acme",
            "version": version,
            "members": [
                {"moss_peer_id": admin_peer, "name": "a", "role": "admin"},
                {"moss_peer_id": member_b, "name": "b", "role": b_role},
                {"moss_peer_id": member_c, "name": "c", "role": "member"},
                {"moss_peer_id": member_d, "name": "d", "role": "member"},
                {"moss_peer_id": member_e, "name": "e", "role": "member"},
            ],
        });
        let bytes = org_roster::sign_roster(&mut doc, &org_key()).unwrap();
        persistence.put_org_roster(&org_key_hex(), &bytes).unwrap();
    };
    put_roster(1, "member");
    let mut runtime =
        PrivateGroupRuntime::from_shared(moss, temp_store(), Some(persistence.clone()));
    let group_id = runtime
        .create_group(CreateGroupRequest {
            label: None,
            display_name: "Alice".to_string(),
            listen_port: 0,
            static_peer: None,
            org_pubkey: Some(org_key_hex()),
        })
        .unwrap()
        .group_id;

    // B and D join; B then authors a real commit adding C.
    let mut b_crypto = MlsSessionCrypto::new(&member_b).unwrap();
    let mut d_crypto = MlsSessionCrypto::new(&member_d).unwrap();
    let (control_channel, mesh_id) = {
        let session = runtime.groups.get_mut(&group_id).unwrap();
        let add_b = session
            .crypto
            .add_members(&[b_crypto.key_package_bytes().unwrap().as_slice()])
            .unwrap();
        b_crypto
            .join_welcome(&add_b.welcome_bytes, &add_b.tree_bytes)
            .unwrap();
        let add_d = session
            .crypto
            .add_members(&[d_crypto.key_package_bytes().unwrap().as_slice()])
            .unwrap();
        b_crypto.process_commit(&add_d.commit_bytes).unwrap();
        (session.control_channel.clone(), session.mesh_id.clone())
    };
    let mut c_crypto = MlsSessionCrypto::new(&member_c).unwrap();
    let b_commit = b_crypto
        .add_members(&[c_crypto.key_package_bytes().unwrap().as_slice()])
        .unwrap();
    let lagged = |key: &SigningKey, commit: &[u8]| {
        let envelope = ControlEnvelope::Commit {
            admission_binding: None,
            group_id: group_id.clone(),
            from_fingerprint: org_signing::peer_id_hex(key),
            commit_b64: encode(commit),
            roster_version: Some(2),
        };
        MossReceivedMessage {
            channel: control_channel.clone(),
            payload: org_signed_control(key, &control_channel, &mesh_id, &envelope),
        }
    };

    let mut e_crypto = MlsSessionCrypto::new(&member_e).unwrap();
    let b_second = b_crypto
        .add_members(&[e_crypto.key_package_bytes().unwrap().as_slice()])
        .unwrap();
    // Control frames skip the replay set, so the first commit can arrive
    // several times before the second; repeats must not take B's slots.
    let mut frames: Vec<_> = (0..ROSTER_LAG_PER_SENDER)
        .map(|_| lagged(&member_b_key, &b_commit.commit_bytes))
        .collect();
    frames.push(lagged(&member_b_key, &b_second.commit_bytes));
    for seed in 0..ROSTER_LAG_CAP as u8 {
        frames.push(lagged(&SigningKey::from_bytes(&[seed; 32]), b"junk"));
        frames.push(lagged(&member_d_key, &[seed]));
    }
    let session = runtime.groups.get_mut(&group_id).unwrap();
    for frame in frames {
        let _ = session.handle_moss_message(frame);
    }

    put_roster(2, "admin");
    session.sync_roster_state(now_ms());
    assert_eq!(
        session.crypto.member_count(),
        5,
        "the promoted admin's two commits add C, then E"
    );
    let _ = std::fs::remove_file(&db_path);
}
