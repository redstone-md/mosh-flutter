use super::*;

/// The catch-up path must land on the same admin as the direct one: a
/// member that only sees the leave commit inside an admin's resync replay
/// derives the successor exactly like everyone else.
#[test]
fn a_member_catching_up_by_resync_lands_on_the_same_admin() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut view = MemberView::open(42392);
    let departed = view.dane.fingerprint();
    // Neither the departure proposal nor the commit reached us live; the
    // admin's log replays the commit, and it stands on its own.
    let leave_commit = view.cleo_commits_departure();
    let successor = view.cleo.member_fingerprints().into_iter().min().unwrap();
    let own_fp = view.session().crypto.fingerprint();

    view.deliver(&ControlEnvelope::ResyncResponse {
        group_id: view.group_id.clone(),
        for_fingerprint: own_fp.clone(),
        commits: vec![ResyncCommit {
            epoch: MlsSessionCrypto::commit_epoch(&leave_commit).unwrap(),
            commit_b64: encode(&leave_commit),
        }],
    });

    let session = view.session();
    assert_eq!(session.crypto.member_count(), 2, "replay must apply");
    assert_ne!(session.current_admin_fingerprint, departed);
    assert_eq!(session.current_admin_fingerprint, successor);
    assert_eq!(session.is_admin, successor == own_fp);
}

/// The other half of #18: when the leave commit itself is the frame that
/// gossip drops, the member's admin pointer is stale and every later
/// commit comes from an author it does not know as its admin. That must
/// not be a silent drop — the commit is one epoch ahead, so it buffers and
/// asks the group for a replay instead of freezing.
#[test]
fn a_commit_from_an_unknown_author_asks_for_a_resync_instead_of_freezing() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut view = MemberView::open(42393);
    // Neither the departure nor the commit that follows it reaches us.
    let _leave_commit = view.cleo_commits_departure();

    // The successor moves the group on: a commit one epoch ahead, from an
    // author the stale member does not know as its admin.
    let mut newcomer = MlsSessionCrypto::new("newcomer").unwrap();
    let kp = newcomer.key_package_bytes().unwrap();
    let ahead = view.cleo.add_members(&[kp.as_slice()]).unwrap();
    view.deliver(&ControlEnvelope::Commit {
        group_id: view.group_id.clone(),
        from_fingerprint: view.cleo.fingerprint(),
        commit_b64: encode(&ahead.commit_bytes),
        roster_version: None,
    });

    let epoch = view.session().crypto.epoch().unwrap();
    let session = view.runtime.groups.get_mut(&view.group_id).unwrap();
    assert_eq!(
        session.crypto.member_count(),
        3,
        "an unattributed commit must never apply"
    );
    assert!(
        !session.sequencer.should_request(epoch),
        "a resync request must already be outstanding for this epoch"
    );
}

// A roster near u64::MAX is absurd but signed, and the lag-horizon check used
// to add ROSTER_LAG_HORIZON with plain `+`: a debug build panicked and a
// release build wrapped the horizon backwards, admitting (instead of
// rejecting) the u64::MAX claim the comment itself calls unreachable.
#[test]
fn a_roster_near_the_version_ceiling_rejects_an_unreachable_claim() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut db_path: PathBuf = std::env::temp_dir();
    db_path.push(format!("mosh-org-horizon-{}.redb", std::process::id()));
    let _ = std::fs::remove_file(&db_path);
    let persistence =
        Arc::new(Persistence::open_with_dek(&db_path, [33u8; 32]).expect("store should open"));

    let admin_seed = [101u8; 32];
    persistence
        .put_moss_identity(&identity_blob(admin_seed))
        .unwrap();
    let admin_peer = org_signing::peer_id_hex(&SigningKey::from_bytes(&admin_seed));
    let member_b_key = SigningKey::from_bytes(&[102u8; 32]);
    let member_b = org_signing::peer_id_hex(&member_b_key);

    // A roster pinned near the ceiling: `own + HORIZON` overflows, which used
    // to panic in debug builds and wrap the horizon backwards in release
    // (admitting the very claim the check exists to reject).
    let mut doc = serde_json::json!({
        "org_pubkey": org_key_hex(),
        "org_name": "acme",
        "version": u64::MAX - (ROSTER_LAG_HORIZON / 2),
        "members": [
            {"moss_peer_id": admin_peer, "name": "a", "role": "admin"},
            {"moss_peer_id": member_b, "name": "b", "role": "member"},
        ],
    });
    let bytes = org_roster::sign_roster(&mut doc, &org_key()).unwrap();
    persistence.put_org_roster(&org_key_hex(), &bytes).unwrap();

    let moss = Arc::new(MossFfiRuntime::load_default().expect("moss should load"));
    let mut runtime =
        PrivateGroupRuntime::from_shared(moss, temp_store(), Some(persistence.clone()));
    let created = runtime
        .create_group(CreateGroupRequest {
            label: None,
            display_name: "Alice".to_string(),
            listen_port: 42391,
            static_peer: None,
            org_pubkey: Some(org_key_hex()),
        })
        .unwrap();

    // B (non-admin) claims the ceiling itself — beyond any horizon, so the
    // buffer must not take it even though `own + HORIZON` would wrap.
    let commit_b64 = encode(b"whatever-commit-bytes");
    let env = ControlEnvelope::Commit {
        group_id: created.group_id.clone(),
        from_fingerprint: "b-fingerprint".to_string(),
        commit_b64,
        roster_version: Some(u64::MAX),
    };
    let (control_channel, mesh_id) = {
        let session = runtime.groups.get(&created.group_id).unwrap();
        (session.control_channel.clone(), session.mesh_id.clone())
    };
    let session = runtime.groups.get_mut(&created.group_id).unwrap();
    let _ = session.handle_moss_message(MossReceivedMessage {
        channel: control_channel.clone(),
        payload: org_signed_control(&member_b_key, &control_channel, &mesh_id, &env),
    });
    {
        let session = runtime.groups.get(&created.group_id).unwrap();
        assert!(
            session.roster_lag.is_empty(),
            "a claim at the ceiling is beyond any horizon and must be dropped, not buffered"
        );
    }

    let _ = std::fs::remove_file(&db_path);
}
