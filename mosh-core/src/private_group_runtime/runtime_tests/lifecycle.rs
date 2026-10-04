use super::*;

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

// A create whose node cannot produce a public key fails — and must not leave
// the room open behind it. On the shared node the acquired reference is what
// keeps moss up, so bailing without closing pins the node (and its
// subscriptions) on a group that never became a session.
#[test]
fn a_create_without_a_public_key_closes_the_room_it_opened() {
    let _guard = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    drain_received_messages();

    let moss = Arc::new(MossFfiRuntime::load_default().expect("moss should load"));
    let mut runtime = PrivateGroupRuntime::from_shared(moss, temp_store(), None);

    let _keyless = crate::moss_ffi::public_key_unavailable_next_node();
    let error = runtime
        .create_group(CreateGroupRequest {
            label: Some("Keyless".to_string()),
            display_name: "Alice".to_string(),
            listen_port: 42390,
            static_peer: None,
            org_pubkey: None,
        })
        .expect_err("a keyless node cannot back a group");
    assert!(
        matches!(error, PrivateGroupError::Moss(_)),
        "the failure is the missing public key, got {error:?}"
    );
    assert!(
        runtime.shared_node.current().is_none(),
        "a create that never became a session must release the shared node"
    );

    // The retry proves the failed create left no wedged state behind.
    runtime
        .create_group(CreateGroupRequest {
            label: Some("Keyless".to_string()),
            display_name: "Alice".to_string(),
            listen_port: 42390,
            static_peer: None,
            org_pubkey: None,
        })
        .expect("the retry holds the node the failed create released");
    assert!(runtime.shared_node.current().is_some());
}
