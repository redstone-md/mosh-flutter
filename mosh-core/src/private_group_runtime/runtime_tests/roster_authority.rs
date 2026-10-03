use super::*;

#[test]
fn org_commit_authority_follows_roster_with_lag_buffer() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut db_path: PathBuf = std::env::temp_dir();
    db_path.push(format!("mosh-org-authority-{}.redb", std::process::id()));
    let _ = std::fs::remove_file(&db_path);
    let persistence =
        Arc::new(Persistence::open_with_dek(&db_path, [29u8; 32]).expect("store should open"));

    let admin_seed = [81u8; 32];
    persistence
        .put_moss_identity(&identity_blob(admin_seed))
        .unwrap();
    let admin_peer = org_signing::peer_id_hex(&SigningKey::from_bytes(&admin_seed));
    let member_b_key = SigningKey::from_bytes(&[82u8; 32]);
    let member_b = org_signing::peer_id_hex(&member_b_key);
    let member_c = hex::encode([0x83u8; 32]);

    let put_roster = |version: u64, b_role: &str| {
        let mut doc = serde_json::json!({
            "org_pubkey": org_key_hex(),
            "org_name": "acme",
            "version": version,
            "members": [
                {"moss_peer_id": admin_peer, "name": "a", "role": "admin"},
                {"moss_peer_id": member_b, "name": "b", "role": b_role},
                {"moss_peer_id": member_c, "name": "c", "role": "member"},
            ],
        });
        let bytes = org_roster::sign_roster(&mut doc, &org_key()).unwrap();
        persistence.put_org_roster(&org_key_hex(), &bytes).unwrap();
    };
    put_roster(1, "member");

    let moss = Arc::new(MossFfiRuntime::load_default().expect("moss should load"));
    let mut runtime =
        PrivateGroupRuntime::from_shared(moss, temp_store(), Some(persistence.clone()));
    let created = runtime
        .create_group(CreateGroupRequest {
            label: None,
            display_name: "Alice".to_string(),
            listen_port: 42370,
            static_peer: None,
            org_pubkey: Some(org_key_hex()),
        })
        .unwrap();

    // Join B directly at the crypto layer so B can author a REAL commit.
    let mut b_crypto = MlsSessionCrypto::new(&member_b).unwrap();
    let kp_b = b_crypto.key_package_bytes().unwrap();
    let (control_channel, mesh_id, welcome, tree) = {
        let session = runtime.groups.get_mut(&created.group_id).unwrap();
        let outcome = session.crypto.add_members(&[kp_b.as_slice()]).unwrap();
        (
            session.control_channel.clone(),
            session.mesh_id.clone(),
            outcome.welcome_bytes,
            outcome.tree_bytes,
        )
    };
    b_crypto.join_welcome(&welcome, &tree).unwrap();

    // B (still role: member) adds C — a real, valid MLS commit.
    let mut c_crypto = MlsSessionCrypto::new(&member_c).unwrap();
    let kp_c = c_crypto.key_package_bytes().unwrap();
    let b_commit = b_crypto.add_members(&[kp_c.as_slice()]).unwrap();
    let commit_from_b = |roster_version: Option<u64>| ControlEnvelope::Commit {
        group_id: created.group_id.clone(),
        from_fingerprint: b_crypto.fingerprint(),
        commit_b64: encode(&b_commit.commit_bytes),
        roster_version,
    };
    let deliver = |runtime: &mut PrivateGroupRuntime, payload: Vec<u8>| {
        let session = runtime.groups.get_mut(&created.group_id).unwrap();
        let _ = session.handle_moss_message(MossReceivedMessage {
            channel: control_channel.clone(),
            payload,
        });
    };

    // Non-admin commit with no version claim: dropped outright.
    let env = commit_from_b(None);
    deliver(
        &mut runtime,
        org_signed_control(&member_b_key, &control_channel, &mesh_id, &env),
    );
    {
        let session = runtime.groups.get_mut(&created.group_id).unwrap();
        assert_eq!(
            session.crypto.member_count(),
            2,
            "non-admin commit must not apply"
        );
        assert!(session.roster_lag.is_empty());
    }

    // Same commit claiming roster v2 (ahead of ours): buffered, not applied.
    let env = commit_from_b(Some(2));
    deliver(
        &mut runtime,
        org_signed_control(&member_b_key, &control_channel, &mesh_id, &env),
    );
    {
        let session = runtime.groups.get_mut(&created.group_id).unwrap();
        assert_eq!(session.crypto.member_count(), 2);
        assert_eq!(
            session.roster_lag.len(),
            1,
            "ahead-of-roster commit buffers"
        );
    }

    // Roster v2 promotes B to admin: the buffered commit now applies.
    put_roster(2, "admin");
    {
        let session = runtime.groups.get_mut(&created.group_id).unwrap();
        session.sync_roster_state();
        assert!(session.roster_lag.is_empty());
        assert_eq!(
            session.crypto.member_count(),
            3,
            "commit applies once author is admin"
        );
    }

    let _ = std::fs::remove_file(&db_path);
}

#[test]
fn roster_reconciliation_kicks_revoked_members_and_survives_restart() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut db_path: PathBuf = std::env::temp_dir();
    db_path.push(format!("mosh-org-kick-{}.redb", std::process::id()));
    let _ = std::fs::remove_file(&db_path);
    let persistence =
        Arc::new(Persistence::open_with_dek(&db_path, [31u8; 32]).expect("store should open"));

    let admin_seed = [91u8; 32];
    persistence
        .put_moss_identity(&identity_blob(admin_seed))
        .unwrap();
    let admin_peer = org_signing::peer_id_hex(&SigningKey::from_bytes(&admin_seed));
    let member_b_key = SigningKey::from_bytes(&[92u8; 32]);
    let member_b = org_signing::peer_id_hex(&member_b_key);

    let put_roster = |version: u64, own_role: &str, with_b: bool| {
        let mut members = vec![serde_json::json!({
            "moss_peer_id": admin_peer, "name": "a", "role": own_role,
        })];
        if with_b {
            members.push(serde_json::json!({
                "moss_peer_id": member_b, "name": "b", "role": "member",
            }));
        }
        let mut doc = serde_json::json!({
            "org_pubkey": org_key_hex(),
            "org_name": "acme",
            "version": version,
            "members": members,
        });
        let bytes = org_roster::sign_roster(&mut doc, &org_key()).unwrap();
        persistence.put_org_roster(&org_key_hex(), &bytes).unwrap();
    };
    put_roster(1, "admin", true);

    let moss = Arc::new(MossFfiRuntime::load_default().expect("moss should load"));
    let mut runtime =
        PrivateGroupRuntime::from_shared(moss, temp_store(), Some(persistence.clone()));
    let created = runtime
        .create_group(CreateGroupRequest {
            label: None,
            display_name: "Alice".to_string(),
            listen_port: 42380,
            static_peer: None,
            org_pubkey: Some(org_key_hex()),
        })
        .unwrap();
    {
        let session = runtime.groups.get_mut(&created.group_id).unwrap();
        let mut b_crypto = MlsSessionCrypto::new(&member_b).unwrap();
        let kp = b_crypto.key_package_bytes().unwrap();
        session.crypto.add_members(&[kp.as_slice()]).unwrap();
        assert_eq!(session.crypto.member_count(), 2);
    }

    let sync = |runtime: &mut PrivateGroupRuntime| {
        runtime
            .groups
            .get_mut(&created.group_id)
            .unwrap()
            .sync_roster_state();
    };

    // Not an admin in the current roster: reconciliation must not kick.
    put_roster(2, "member", true);
    sync(&mut runtime);
    assert_eq!(
        runtime
            .groups
            .get(&created.group_id)
            .unwrap()
            .crypto
            .member_count(),
        2,
        "non-admin client must not author the kick"
    );

    // Admin again and B revoked: the kick commit lands and is logged.
    put_roster(3, "admin", false);
    sync(&mut runtime);
    {
        let session = runtime.groups.get(&created.group_id).unwrap();
        assert_eq!(
            session.crypto.member_count(),
            1,
            "revoked member must be removed"
        );
        assert!(
            !session.crypto.member_identities().contains(&member_b),
            "revoked peer-id must not keep a leaf"
        );
    }
    assert!(
        !persistence
            .list_group_commits_from(&created.group_id, 0)
            .unwrap()
            .is_empty(),
        "kick commit must be logged for resync"
    );
    // Repeat sync at the same version: no further commits (idempotent).
    let logged = persistence
        .list_group_commits_from(&created.group_id, 0)
        .unwrap()
        .len();
    sync(&mut runtime);
    assert_eq!(
        persistence
            .list_group_commits_from(&created.group_id, 0)
            .unwrap()
            .len(),
        logged
    );

    // Restart scenario (the PR #22 review red): the roster removal was
    // absorbed while the admin never polled this org, then the app
    // restarted. Reconciliation runs from durable state on rehydrate.
    drop(runtime);
    let moss = Arc::new(MossFfiRuntime::load_default().expect("moss should load"));
    let mut revived =
        PrivateGroupRuntime::from_shared(moss, temp_store(), Some(persistence.clone()));
    revived.rehydrate();
    // Simulate a stale MLS tree by re-adding B behind the roster's back,
    // then let the drain-driven sync converge it.
    {
        let session = revived.groups.get_mut(&created.group_id).unwrap();
        let mut b_again = MlsSessionCrypto::new(&member_b).unwrap();
        let kp = b_again.key_package_bytes().unwrap();
        session.crypto.add_members(&[kp.as_slice()]).unwrap();
        assert_eq!(session.crypto.member_count(), 2);
        session.last_roster_version_seen = None;
        session.sync_roster_state();
        assert_eq!(
            session.crypto.member_count(),
            1,
            "reconciliation must kick from persisted state after restart"
        );
    }

    let _ = std::fs::remove_file(&db_path);
}

/// #18: the admin's departure travels in the Commit that drops its leaf,
/// not in the best-effort `AdminHandoff` frame. No handoff is sent here
/// at all; the member must still land on the deterministic successor.
#[test]
fn admin_departure_is_derived_from_the_commit_not_the_handoff() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut view = MemberView::open(42391);
    let departed = view.dane.fingerprint();
    let leave_commit = view.cleo_commits_departure();
    // What every remaining member derives from the same tree.
    let successor = view.cleo.member_fingerprints().into_iter().min().unwrap();

    view.deliver(&ControlEnvelope::Commit {
        group_id: view.group_id.clone(),
        from_fingerprint: view.cleo.fingerprint(),
        commit_b64: encode(&leave_commit),
        roster_version: None,
    });

    let session = view.session();
    assert_eq!(session.crypto.member_count(), 2, "commit must apply");
    assert_ne!(
        session.current_admin_fingerprint, departed,
        "the departed admin must not stay the admin"
    );
    assert_eq!(session.current_admin_fingerprint, successor);
    assert_eq!(session.is_admin, successor == session.crypto.fingerprint());
}

/// Nobody can commit their own removal — MLS forbids it — so every
/// departure is a proposal someone who stays commits. An ordinary member's
/// is committed by the admin; the admin's by the successor, which then
/// takes over.
#[test]
fn departures_are_committed_by_the_admin_then_by_the_successor() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut view = MemberView::open(42394);
    let own_fp = view.session().crypto.fingerprint();
    let group_id = view.group_id.clone();

    // `cleo` leaves. We are not the admin, so we must not commit it.
    let cleo_departure = MemberView::departure_of(&mut view.cleo, &group_id);
    view.deliver(&cleo_departure);
    assert_eq!(
        view.session().crypto.member_count(),
        3,
        "only the admin commits an ordinary member's departure"
    );

    // The admin commits it, and we merge the commit like any third party —
    // which needs the removal to ride inside the commit, since we never
    // stored the proposal.
    let ControlEnvelope::SelfRemove { proposal_b64, .. } = &cleo_departure else {
        unreachable!("built as a SelfRemove");
    };
    let commit = view
        .dane
        .commit_departure(&decode(proposal_b64).unwrap())
        .unwrap();
    view.deliver(&ControlEnvelope::Commit {
        group_id: group_id.clone(),
        from_fingerprint: view.dane.fingerprint(),
        commit_b64: encode(&commit),
        roster_version: None,
    });
    assert_eq!(view.session().crypto.member_count(), 2);

    // Now the admin leaves. We are the only member left, so the successor
    // rule names us: we commit, and the same commit makes us the admin.
    let admin_departure = MemberView::departure_of(&mut view.dane, &group_id);
    view.deliver(&admin_departure);

    let session = view.session();
    assert_eq!(session.crypto.member_count(), 1, "successor must commit");
    assert_eq!(session.current_admin_fingerprint, own_fp);
    assert!(session.is_admin, "the committer is the new admin");
}
