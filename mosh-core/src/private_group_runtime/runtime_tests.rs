//! The group runtime tests: state machine, org authority, resync.
use super::*;
use crate::moss_ffi::{
    drain_received_messages, fail_next_test_publish, no_peers_next_test_publish, MossFfiRuntime,
    MOSS_TEST_LOCK,
};
use crate::persistence::Persistence;
use std::path::PathBuf;

fn temp_store() -> Arc<AttachmentStore> {
    let mut path = std::env::temp_dir();
    path.push(format!(
        "mosh-group-attachments-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    Arc::new(AttachmentStore::new(&path).expect("attachment store should init"))
}

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
fn invite_uri_round_trips() {
    let uri = build_invite_uri(
        "groupmesh-aaa",
        "group-bbb",
        "AABBCCDDEEFF00112233445566778899",
        &Some("Friends".to_string()),
    );
    let parsed = ParsedGroupInvite::parse(&uri).unwrap();
    assert_eq!(parsed.mesh_id, "groupmesh-aaa");
    assert_eq!(parsed.group_id, "group-bbb");
    assert_eq!(
        parsed.creator_fingerprint,
        "AABBCCDDEEFF00112233445566778899"
    );
    assert_eq!(parsed.label.as_deref(), Some("Friends"));
}

#[test]
fn invite_uri_without_label() {
    let uri = build_invite_uri("m", "g", "00112233445566778899AABBCCDDEEFF", &None);
    let parsed = ParsedGroupInvite::parse(&uri).unwrap();
    assert!(parsed.label.is_none());
}

#[test]
fn invite_uri_rejects_malformed_fingerprint() {
    let short = format!("{INVITE_PREFIX}?mesh=m&group=g#fp=ABCD");
    assert!(matches!(
        ParsedGroupInvite::parse(&short),
        Err(PrivateGroupError::InvalidInvite(_))
    ));
    let non_hex = format!("{INVITE_PREFIX}?mesh=m&group=g#fp=ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ");
    assert!(matches!(
        ParsedGroupInvite::parse(&non_hex),
        Err(PrivateGroupError::InvalidInvite(_))
    ));
}

#[test]
fn channel_group_id_strips_prefix() {
    assert_eq!(channel_group_id("group-control/g-1"), Some("g-1"));
    assert_eq!(channel_group_id("group-data/g-1"), Some("g-1"));
    assert_eq!(channel_group_id("public-channel/x"), None);
}

fn org_key() -> SigningKey {
    SigningKey::from_bytes(&[61u8; 32])
}

fn org_key_hex() -> String {
    hex::encode(org_key().verifying_key().to_bytes())
}

fn identity_blob(seed: [u8; 32]) -> Vec<u8> {
    let key = SigningKey::from_bytes(&seed);
    let mut blob = vec![1u8];
    blob.extend_from_slice(&seed);
    blob.extend_from_slice(&key.verifying_key().to_bytes());
    blob.extend_from_slice(&[0u8; 64]);
    blob
}

fn put_signed_roster(p: &Persistence, members: &[(&str, &str)]) {
    let mut doc = serde_json::json!({
        "org_pubkey": org_key_hex(),
        "org_name": "acme",
        "version": 1,
        "members": members
            .iter()
            .map(|(id, role)| serde_json::json!({
                "moss_peer_id": id, "name": "m", "role": role,
            }))
            .collect::<Vec<_>>(),
    });
    let bytes = org_roster::sign_roster(&mut doc, &org_key()).unwrap();
    p.put_org_roster(&org_key_hex(), &bytes).unwrap();
}

fn org_signed_control(
    sender: &SigningKey,
    session_channel: &str,
    mesh_id: &str,
    envelope: &ControlEnvelope,
) -> Vec<u8> {
    let org = org_key_hex();
    let ctx = OrgContext {
        org_pubkey: &org,
        mesh_id,
        channel_kind: session_channel,
    };
    let env = org_envelope::sign(sender, &ctx, &serde_json::to_vec(envelope).unwrap());
    serde_json::to_vec(&env).unwrap()
}

// Every group now shares one moss node, so a group's own room is what
// separates it from the others — and the node outliving the group is a new
// failure mode: nothing ends its subscriptions unless close says so.
#[test]
fn groups_share_one_node_and_close_releases_it() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let moss = Arc::new(MossFfiRuntime::load_default().expect("moss should load"));
    let mut runtime = PrivateGroupRuntime::from_shared(moss, temp_store(), None);
    let first = runtime
        .create_group(CreateGroupRequest {
            label: Some("First".to_string()),
            display_name: "Alice".to_string(),
            listen_port: 42370,
            static_peer: None,
            org_pubkey: None,
        })
        .expect("first group should be created");
    let second = runtime
        .create_group(CreateGroupRequest {
            label: Some("Second".to_string()),
            display_name: "Alice".to_string(),
            listen_port: 42371,
            static_peer: None,
            org_pubkey: None,
        })
        .expect("second group should be created");

    // One node, not two. Two would present the same peer id from two ports
    // and a remote peer would keep only the first.
    let first_node = Arc::as_ptr(
        &runtime
            .groups
            .get(&first.group_id)
            .expect("first group")
            .node,
    );
    let second_node = Arc::as_ptr(
        &runtime
            .groups
            .get(&second.group_id)
            .expect("second group")
            .node,
    );
    assert_eq!(
        first_node, second_node,
        "two open groups started two moss nodes under one identity"
    );
    assert_ne!(
        first.mesh_id, second.mesh_id,
        "groups must stay in separate rooms on the shared node"
    );

    runtime.close(&first.group_id).expect("first should close");
    assert!(
        runtime.shared_node.current().is_some(),
        "the shared node went down while a group was still open"
    );
    runtime
        .close(&second.group_id)
        .expect("second should close");
    assert!(
        runtime.shared_node.current().is_none(),
        "the shared node outlived every group — nothing would ever stop moss"
    );
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

// Regression: Moss answering "no peers" used to count as a successful
// publish, so a message nobody could receive showed as Sent. A group has
// no acknowledgement and no resend loop, so the refusal has to land as a
// retryable failure the user can act on.
#[test]
fn no_peers_does_not_count_as_sent() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
    let mut groups = PrivateGroupRuntime::from_shared(runtime, temp_store(), None);
    let created = groups
        .create_group(CreateGroupRequest {
            label: Some("Empty Club".to_string()),
            display_name: "Alice".to_string(),
            listen_port: 42242,
            static_peer: None,
            org_pubkey: None,
        })
        .expect("group should be created");

    let _no_peers = no_peers_next_test_publish();
    let result = groups
        .send(&created.group_id, "nobody is here".to_string())
        .expect("send should return a result");

    assert_eq!(result.delivery_status, MessageDeliveryStatus::Failed);
    assert_eq!(
        result.delivery_error.as_deref(),
        Some("Moss error: no peers yet, so the message did not go out")
    );

    let live = groups.poll(&created.group_id).expect("poll should pass");
    let message = live
        .messages
        .iter()
        .find(|message| message.message_id.as_deref() == Some(result.message_id.as_str()))
        .expect("the message should be recorded");
    assert_eq!(message.delivery_status, Some(MessageDeliveryStatus::Failed));
    assert_eq!(message.retryable, Some(true));

    // The attempt record survived the failure, so the existing retry path
    // replays the same bytes without new machinery.
    let retried = groups
        .retry_message(&created.group_id, &result.message_id)
        .expect("retry should succeed once a peer is there");
    assert_eq!(retried.delivery_status, MessageDeliveryStatus::Sent);
}

#[test]
fn failed_send_rehydrates_as_retryable_message() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut db_path: PathBuf = std::env::temp_dir();
    db_path.push(format!(
        "mosh-group-failed-send-{}.redb",
        std::process::id()
    ));
    let _ = std::fs::remove_file(&db_path);

    let persistence =
        Arc::new(Persistence::open_with_dek(&db_path, [21u8; 32]).expect("store should open"));
    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));

    let (group_id, message_id) = {
        let mut groups = PrivateGroupRuntime::from_shared(
            Arc::clone(&runtime),
            temp_store(),
            Some(persistence.clone()),
        );
        let created = groups
            .create_group(CreateGroupRequest {
                label: Some("Retry Club".to_string()),
                display_name: "Alice".to_string(),
                listen_port: 42241,
                static_peer: None,
                org_pubkey: None,
            })
            .expect("group should be created");
        let _publish_fail = fail_next_test_publish("simulated publish failure");
        let result = groups
            .send(&created.group_id, "hello failed group".to_string())
            .expect("send should return failed result");
        assert_eq!(result.delivery_status, MessageDeliveryStatus::Failed);
        assert_eq!(
            result.delivery_error.as_deref(),
            Some("Moss error: simulated publish failure")
        );

        let live = groups
            .poll(&created.group_id)
            .expect("poll should surface failed message");
        let failed = live
            .messages
            .iter()
            .find(|message| message.message_id.as_deref() == Some(result.message_id.as_str()))
            .expect("failed message should be recorded");
        assert_eq!(failed.delivery_status, Some(MessageDeliveryStatus::Failed));
        assert_eq!(failed.retryable, Some(true));

        (created.group_id, result.message_id)
    };

    let mut revived =
        PrivateGroupRuntime::from_shared(Arc::clone(&runtime), temp_store(), Some(persistence));
    revived.rehydrate();
    let listing = revived.list().expect("listing should pass");
    let group = listing
        .groups
        .iter()
        .find(|group| group.group_id == group_id)
        .expect("rehydrated group should be present");
    let failed = group
        .messages
        .iter()
        .find(|message| message.message_id.as_deref() == Some(message_id.as_str()))
        .expect("failed message should rehydrate");
    assert_eq!(failed.delivery_status, Some(MessageDeliveryStatus::Failed));
    assert_eq!(failed.retryable, Some(true));

    let _ = std::fs::remove_file(&db_path);
}

#[test]
fn retry_message_reuses_message_id_and_clears_failed_attempt() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut db_path: PathBuf = std::env::temp_dir();
    db_path.push(format!("mosh-group-retry-{}.redb", std::process::id()));
    let _ = std::fs::remove_file(&db_path);

    let persistence =
        Arc::new(Persistence::open_with_dek(&db_path, [22u8; 32]).expect("store should open"));
    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));

    let (group_id, failed_message_id) = {
        let mut groups = PrivateGroupRuntime::from_shared(
            Arc::clone(&runtime),
            temp_store(),
            Some(persistence.clone()),
        );
        let created = groups
            .create_group(CreateGroupRequest {
                label: Some("Retry Club".to_string()),
                display_name: "Alice".to_string(),
                listen_port: 42242,
                static_peer: None,
                org_pubkey: None,
            })
            .expect("group should be created");
        let _publish_fail = fail_next_test_publish("simulated publish failure");
        let failed = groups
            .send(&created.group_id, "retry this group message".to_string())
            .expect("failed send should still return a result");

        let retried = groups
            .retry_message(&created.group_id, &failed.message_id)
            .expect("retry should succeed");
        assert_eq!(retried.message_id, failed.message_id);
        assert_eq!(retried.delivery_status, MessageDeliveryStatus::Sent);

        let snapshot = groups.poll(&created.group_id).expect("poll should pass");
        let matching: Vec<&GroupMessage> = snapshot
            .messages
            .iter()
            .filter(|message| message.message_id.as_deref() == Some(failed.message_id.as_str()))
            .collect();
        assert_eq!(
            matching.len(),
            1,
            "retry should update, not duplicate, the row"
        );
        assert_eq!(
            matching[0].delivery_status,
            Some(MessageDeliveryStatus::Sent)
        );
        assert_eq!(matching[0].retry_count, Some(1));

        (created.group_id, failed.message_id)
    };

    let stored_attempt = persistence
        .get_outbound_attempt("private_group", &group_id, &failed_message_id)
        .expect("lookup should pass");
    assert!(stored_attempt.is_none());

    let _ = std::fs::remove_file(&db_path);
}

/// A three-party plain group whose runtime session is an ordinary member.
/// The admin (`dane`) and the third member (`cleo`) live at the crypto
/// layer, so a real admin departure can be replayed against a real
/// session and the member's view inspected.
struct MemberView {
    runtime: PrivateGroupRuntime,
    group_id: String,
    control_channel: String,
    dane: MlsSessionCrypto,
    cleo: MlsSessionCrypto,
}

impl MemberView {
    fn open(listen_port: u16) -> Self {
        let moss = Arc::new(MossFfiRuntime::load_default().expect("moss should load"));
        let mut runtime = PrivateGroupRuntime::from_shared(moss, temp_store(), None);
        let created = runtime
            .create_group(CreateGroupRequest {
                label: None,
                display_name: "Mia".to_string(),
                listen_port,
                static_peer: None,
                org_pubkey: None,
            })
            .expect("group should be created");

        let mut dane = MlsSessionCrypto::new("dane").unwrap();
        let mut cleo = MlsSessionCrypto::new("cleo").unwrap();
        let control_channel = {
            let session = runtime.groups.get_mut(&created.group_id).unwrap();
            let kp_dane = dane.key_package_bytes().unwrap();
            let add_dane = session.crypto.add_members(&[kp_dane.as_slice()]).unwrap();
            dane.join_welcome(&add_dane.welcome_bytes, &add_dane.tree_bytes)
                .unwrap();
            let kp_cleo = cleo.key_package_bytes().unwrap();
            let add_cleo = session.crypto.add_members(&[kp_cleo.as_slice()]).unwrap();
            cleo.join_welcome(&add_cleo.welcome_bytes, &add_cleo.tree_bytes)
                .unwrap();
            dane.process_commit(&add_cleo.commit_bytes).unwrap();
            // The session is a plain member and `dane` is the admin it
            // points at — the state every non-creator member is in.
            session.is_admin = false;
            session.current_admin_fingerprint = dane.fingerprint();
            session.control_channel.clone()
        };
        Self {
            runtime,
            group_id: created.group_id,
            control_channel,
            dane,
            cleo,
        }
    }

    fn deliver(&mut self, envelope: &ControlEnvelope) {
        let payload = serde_json::to_vec(envelope).unwrap();
        let session = self.runtime.groups.get_mut(&self.group_id).unwrap();
        session
            .handle_moss_message(MossReceivedMessage {
                channel: self.control_channel.clone(),
                payload,
            })
            .expect("control frame should be handled");
    }

    fn session(&self) -> &GroupSession {
        self.runtime.groups.get(&self.group_id).unwrap()
    }

    /// A departure frame: a self-removal proposal, the only way MLS lets a
    /// member retire its own leaf.
    fn departure_of(leaver: &mut MlsSessionCrypto, group_id: &str) -> ControlEnvelope {
        ControlEnvelope::SelfRemove {
            group_id: group_id.to_string(),
            from_fingerprint: leaver.fingerprint(),
            proposal_b64: encode(&leaver.leave_proposal_bytes().unwrap()),
        }
    }

    /// `cleo` commits the admin's departure, as the successor would.
    /// Returns the commit that drops the admin's leaf.
    fn cleo_commits_departure(&mut self) -> Vec<u8> {
        let proposal = self.dane.leave_proposal_bytes().unwrap();
        self.cleo.commit_departure(&proposal).unwrap()
    }

    /// Cleo's typing hint, encrypted under cleo's MLS state — exactly
    /// what a member's runtime mints — delivered to us on the control
    /// channel.
    fn deliver_cleo_typing(&mut self) {
        let body = GroupTypingBody {
            device: "cleo".to_string(),
            until_ms: TypingGate::deadline(now_ms()),
        };
        let ciphertext = self
            .cleo
            .encrypt(&serde_json::to_vec(&body).unwrap())
            .unwrap();
        self.deliver(&ControlEnvelope::TypingIndicator {
            group_id: self.group_id.clone(),
            from_device: "cleo".to_string(),
            from_fingerprint: self.cleo.fingerprint(),
            typing_ciphertext_b64: encode(&ciphertext),
        });
    }

    fn typing_member_of(&self) -> Option<TypingMember> {
        self.session().typing_members_live().first().cloned()
    }
}

/// Cleo types, the member sees WHO types, the sender's message clears
/// the hint, and a forged hint is dead on arrival.
#[test]
fn group_typing_identifies_the_member_and_stops_on_their_message() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut view = MemberView::open(42395);

    // Cleo's hint lands: the snapshot names cleo (fingerprint + display
    // name) with a receiver-stamped deadline.
    view.deliver_cleo_typing();
    let member = view.typing_member_of().expect("cleo's hint must stand");
    assert_eq!(member.fingerprint, view.cleo.fingerprint());
    assert_eq!(member.display_name, "cleo");
    assert!(
        member.until_ms > now_ms(),
        "the deadline is stamped from the receiver's clock"
    );

    // A refresh renews the same entry (no duplicate rows for one member).
    view.deliver_cleo_typing();
    assert_eq!(view.session().typing_members_live().len(), 1);

    // Cleo's own message contradicts "typing": the hint dies at once.
    let body = b"cleo is done typing".to_vec();
    let ciphertext = view.cleo.encrypt(&body).unwrap();
    let data = DataEnvelope {
        group_id: view.group_id.clone(),
        participant_id: "cleo-participant".to_string(),
        from_device: "cleo".to_string(),
        from_fingerprint: view.cleo.fingerprint(),
        message_id: Some("g-typing-1".to_string()),
        sent_at_ms: Some(now_ms()),
        ciphertext_b64: encode(&ciphertext),
    };
    let session = view.runtime.groups.get_mut(&view.group_id).unwrap();
    session
        .handle_moss_message(MossReceivedMessage {
            channel: session.data_channel.clone(),
            payload: serde_json::to_vec(&data).unwrap(),
        })
        .expect("cleo's message should be handled");
    assert!(
        view.typing_member_of().is_none(),
        "a member's own message clears their hint"
    );
}

// A hint that never decrypts (an outsider's bytes) leaves the roster
// empty: the MLS decrypt is the only door, same as the DM side.
#[test]
fn a_forged_group_hint_is_dropped() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let mut view = MemberView::open(42396);
    view.deliver(&ControlEnvelope::TypingIndicator {
        group_id: view.group_id.clone(),
        from_device: "stranger".to_string(),
        from_fingerprint: "stranger-fingerprint".to_string(),
        typing_ciphertext_b64: encode(b"not-an-mls-ciphertext"),
    });
    assert!(view.typing_member_of().is_none());
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

// ---- rehydrate snapshot hygiene ---------------------------------------
//
// A group record whose MLS snapshot is missing can never rebuild. A
// joiner placeholder (not joined, empty MLS group id) is dead data and
// gets deleted at rehydrate; a real record missing its snapshot stays on
// disk (its history rows remain recoverable) and is skipped with a
// distinct warning.

/// A per-test redb path, so rehydrate tests never share one store.
fn rehydrate_db(name: &str) -> PathBuf {
    let mut path = std::env::temp_dir();
    path.push(format!(
        "mosh-group-rehydrate-{name}-{}.redb",
        std::process::id()
    ));
    let _ = std::fs::remove_file(&path);
    path
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
    };
    crate::conversation::history::History::new(GROUP_HISTORY).write_record(
        &persistence,
        "group-orphan",
        &record,
    );
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
    };
    crate::conversation::history::History::new(GROUP_HISTORY).write_record(
        &persistence,
        "group-corrupt",
        &record,
    );
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

/// The group records off disk, through the kind's own history reader.
fn persisted_group_rows(persistence: &Persistence) -> Vec<PersistedGroupSession> {
    crate::conversation::history::History::new(GROUP_HISTORY).stored_conversations(persistence)
}
