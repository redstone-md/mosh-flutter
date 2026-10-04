use super::*;

#[test]
fn blob_round_trips() {
    let dek = [7u8; 32];
    let blob = encrypt_blob(&dek, b"hello history").unwrap();
    assert_ne!(&blob[12..], b"hello history");
    assert_eq!(decrypt_blob(&dek, &blob).unwrap(), b"hello history");
}

#[test]
fn tamper_fails() {
    let dek = [7u8; 32];
    let mut blob = encrypt_blob(&dek, b"secret").unwrap();
    let last = blob.len() - 1;
    blob[last] ^= 0xFF;
    assert!(decrypt_blob(&dek, &blob).is_err());
}

#[test]
fn org_roster_roundtrip_multi_org() {
    let temp = tempfile_db();
    let p = Persistence::open_with_dek(&temp.0, [1u8; 32]).unwrap();

    p.put_org_roster("aa11", b"roster-a-v1").unwrap();
    p.put_org_roster("bb22", b"roster-b-v1").unwrap();
    p.put_org_roster("aa11", b"roster-a-v2").unwrap(); // overwrite = latest wins
    assert_eq!(p.get_org_roster("aa11").unwrap().unwrap(), b"roster-a-v2");
    assert_eq!(p.get_org_roster("none").unwrap(), None);
    let all = p.list_org_rosters().unwrap();
    assert_eq!(all.len(), 2);
    assert!(all.iter().any(|(k, v)| k == "bb22" && v == b"roster-b-v1"));
}

#[test]
fn group_commit_log_ordered_range() {
    let temp = tempfile_db();
    let p = Persistence::open_with_dek(&temp.0, [1u8; 32]).unwrap();

    p.append_group_commit("g1", 2, b"c2").unwrap();
    p.append_group_commit("g1", 10, b"c10").unwrap();
    p.append_group_commit("g1", 3, b"c3").unwrap();
    p.append_group_commit("g2", 1, b"other").unwrap();
    let commits = p.list_group_commits_from("g1", 3).unwrap();
    assert_eq!(commits, vec![(3, b"c3".to_vec()), (10, b"c10".to_vec())]);
    assert!(p.list_group_commits_from("g3", 0).unwrap().is_empty());

    // '/' in group_id would collide with a sibling group's key space.
    assert!(p.append_group_commit("g1/x", 1, b"evil").is_err());
}

#[test]
fn moss_identity_round_trips() {
    let temp = tempfile_db();
    let p = Persistence::open_with_dek(&temp.0, [3u8; 32]).unwrap();

    assert!(p.get_moss_identity().unwrap().is_none());
    let identity = vec![9u8; 129];
    p.put_moss_identity(&identity).unwrap();
    assert_eq!(p.get_moss_identity().unwrap(), Some(identity));
}

#[test]
fn delete_session_removes_record_snapshot_and_messages() {
    let temp = tempfile_db();
    let p = Persistence::open_with_dek(&temp.0, [5u8; 32]).unwrap();

    p.put_session("s1", b"rec").unwrap();
    p.put_mls_snapshot("s1", b"snap").unwrap();
    p.append_message("s1", 1, "m1", b"hi").unwrap();
    p.append_message("s1", 2, "m2", b"yo").unwrap();
    // Unrelated conversation must survive.
    p.put_session("s2", b"rec2").unwrap();
    p.append_message("s2", 1, "x", b"keep").unwrap();

    p.delete_session("s1").unwrap();

    assert!(p.get_mls_snapshot("s1").unwrap().is_none());
    assert!(p.list_messages("s1").unwrap().is_empty());
    assert_eq!(p.list_sessions().unwrap().len(), 1);
    assert_eq!(p.list_messages("s2").unwrap().len(), 1);
}

#[test]
fn messages_round_trip_in_time_order() {
    let temp = tempfile_db();
    let p = Persistence::open_with_dek(&temp.0, [3u8; 32]).unwrap();

    p.append_message("conv-A", 200, "m2", b"second").unwrap();
    p.append_message("conv-A", 100, "m1", b"first").unwrap();
    p.append_message("conv-B", 150, "x", b"other").unwrap();

    let msgs = p.list_messages("conv-A").unwrap();
    assert_eq!(msgs, vec![b"first".to_vec(), b"second".to_vec()]);
}

#[test]
fn messages_ordered_within_same_millisecond_batch() {
    let temp = tempfile_db();
    let p = Persistence::open_with_dek(&temp.0, [5u8; 32]).unwrap();

    let ts = 1_700_000_000_000u64;
    // Padded message indices preserve order within one millisecond.
    for i in (0..12u32).rev() {
        let id = format!("{ts}-{i:06}");
        let body = format!("m{i}");
        p.append_message("conv", ts, &id, body.as_bytes()).unwrap();
    }
    let got: Vec<String> = p
        .list_messages("conv")
        .unwrap()
        .into_iter()
        .map(|b| String::from_utf8(b).unwrap())
        .collect();
    let want: Vec<String> = (0..12).map(|i| format!("m{i}")).collect();
    assert_eq!(got, want, "same-ms messages must come back in index order");
}

#[test]
fn group_records_messages_and_snapshot_round_trip_then_delete() {
    let temp = tempfile_db();
    let p = Persistence::open_with_dek(&temp.0, [11u8; 32]).unwrap();

    p.put_group("g1", br#"{"group_id":"g1"}"#).unwrap();
    p.put_group_mls_snapshot("g1", b"group-snapshot").unwrap();
    p.append_group_message("g1", 20, "m2", br#"{"body":"second"}"#)
        .unwrap();
    p.append_group_message("g1", 10, "m1", br#"{"body":"first"}"#)
        .unwrap();

    assert_eq!(p.list_groups().unwrap().len(), 1);
    assert_eq!(
        p.get_group_mls_snapshot("g1").unwrap().unwrap(),
        b"group-snapshot"
    );
    let rows = p.list_group_messages("g1").unwrap();
    assert_eq!(rows[0], br#"{"body":"first"}"#);
    assert_eq!(rows[1], br#"{"body":"second"}"#);

    p.delete_group("g1").unwrap();
    assert!(p.list_groups().unwrap().is_empty());
    assert!(p.get_group_mls_snapshot("g1").unwrap().is_none());
    assert!(p.list_group_messages("g1").unwrap().is_empty());
}

#[test]
fn channel_records_and_messages_round_trip_then_delete() {
    let temp = tempfile_db();
    let p = Persistence::open_with_dek(&temp.0, [15u8; 32]).unwrap();

    p.put_channel("general", br#"{"name":"general"}"#).unwrap();
    p.append_channel_message("general", 20, "m2", br#"{"body":"second"}"#)
        .unwrap();
    p.append_channel_message("general", 10, "m1", br#"{"body":"first"}"#)
        .unwrap();

    assert_eq!(p.list_channels().unwrap().len(), 1);
    let rows = p.list_channel_messages("general").unwrap();
    assert_eq!(rows[0], br#"{"body":"first"}"#);
    assert_eq!(rows[1], br#"{"body":"second"}"#);

    p.delete_channel("general").unwrap();
    assert!(p.list_channels().unwrap().is_empty());
    assert!(p.list_channel_messages("general").unwrap().is_empty());
}

#[test]
fn outbound_attempts_round_trip_in_order_and_delete_with_conversation() {
    let temp = tempfile_db();
    let p = Persistence::open_with_dek(&temp.0, [21u8; 32]).unwrap();

    p.put_outbound_attempt("private_dm", "s1", "m2", br#"{"message_id":"m2"}"#)
        .unwrap();
    p.put_outbound_attempt("private_dm", "s1", "m1", br#"{"message_id":"m1"}"#)
        .unwrap();
    p.put_outbound_attempt("private_group", "g1", "gm1", br#"{"message_id":"gm1"}"#)
        .unwrap();
    p.put_outbound_attempt("channel", "general", "cm1", br#"{"message_id":"cm1"}"#)
        .unwrap();

    assert_eq!(
        p.get_outbound_attempt("private_dm", "s1", "m1")
            .unwrap()
            .unwrap(),
        br#"{"message_id":"m1"}"#
    );
    assert_eq!(
        p.list_outbound_attempts("private_dm", "s1").unwrap(),
        vec![
            br#"{"message_id":"m1"}"#.to_vec(),
            br#"{"message_id":"m2"}"#.to_vec()
        ]
    );

    p.delete_session("s1").unwrap();
    p.delete_group("g1").unwrap();
    p.delete_channel("general").unwrap();

    assert!(p
        .list_outbound_attempts("private_dm", "s1")
        .unwrap()
        .is_empty());
    assert!(p
        .list_outbound_attempts("private_group", "g1")
        .unwrap()
        .is_empty());
    assert!(p
        .list_outbound_attempts("channel", "general")
        .unwrap()
        .is_empty());
}

/// Host-injected keys survive reopen without touching OS key storage.
#[test]
fn open_with_dek_round_trips_session_across_reopen_without_keychain() {
    let temp = tempfile_db();
    let path = &temp.0;
    let dek = [42u8; 32];

    // First open under the injected DEK: write a session row.
    {
        let p = Persistence::open_with_dek(path, dek).expect("first open_with_dek");
        p.put_session("m3-session", b"{\"hello\":\"inject\"}")
            .expect("session should persist under injected DEK");
    }

    // Reopen the SAME path with the SAME injected DEK: the row must
    // decrypt and round-trip. A wrong DEK here would surface as a redb
    // Crypto decrypt failure (the mismatch the inject path defers to
    // read time).
    {
        let p = Persistence::open_with_dek(path, dek).expect("reopen open_with_dek");
        let sessions = p.list_sessions().expect("sessions should list");
        assert!(
            sessions.iter().any(|row| row == b"{\"hello\":\"inject\"}"),
            "persisted session must round-trip and decrypt under the injected DEK: {sessions:?}"
        );
    }
}
struct TempDatabase(std::path::PathBuf);
impl Drop for TempDatabase {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}
fn tempfile_db() -> TempDatabase {
    TempDatabase(
        std::env::temp_dir().join(format!("mosh-persistence-{}.redb", rand::random::<u64>())),
    )
}
