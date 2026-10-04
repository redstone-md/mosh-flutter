use super::*;

#[test]
fn restore_keeps_sending() {
    let mut alice = MlsSessionCrypto::new("alice").unwrap();
    alice.create_group().unwrap();
    let mut bob = MlsSessionCrypto::new("bob").unwrap();
    let bob_kp = bob.key_package_bytes().unwrap();
    let (welcome, tree) = alice.add_peer(&bob_kp).unwrap();
    bob.join_welcome(&welcome, &tree).unwrap();

    let snap = alice.snapshot();
    let pubkey = alice.signer_public();
    let gid = alice.group_id_bytes().unwrap();
    drop(alice);
    let mut alice2 = MlsSessionCrypto::restore("alice", &pubkey, &snap, &gid).unwrap();

    let ct = alice2.encrypt(b"after restart").unwrap();
    let pt = bob.decrypt(&ct).unwrap();
    assert_eq!(pt, b"after restart");
}

// Reproduces the field bug: after both sides have already exchanged a
// message (so their own sender ratchet has advanced past generation 0),
// a snapshot/restore must still let each side send AND receive. The joiner
// (Bob) restoring and then sending is the reported failure
// ("secret deleted to preserve forward secrecy").
#[test]
fn restore_keeps_sending_after_generation_advance() {
    let mut alice = MlsSessionCrypto::new("alice").unwrap();
    alice.create_group().unwrap();
    let mut bob = MlsSessionCrypto::new("bob").unwrap();
    let bob_kp = bob.key_package_bytes().unwrap();
    let (welcome, tree) = alice.add_peer(&bob_kp).unwrap();
    bob.join_welcome(&welcome, &tree).unwrap();

    // Generation 0 consumed on both sender ratchets.
    let c1 = alice.encrypt(b"a1").unwrap();
    assert_eq!(bob.decrypt(&c1).unwrap(), b"a1");
    let r1 = bob.encrypt(b"b1").unwrap();
    assert_eq!(alice.decrypt(&r1).unwrap(), b"b1");

    // Snapshot + restore BOTH after the advance.
    let restore = |c: &MlsSessionCrypto, id: &str| {
        MlsSessionCrypto::restore(
            id,
            &c.signer_public(),
            &c.snapshot(),
            &c.group_id_bytes().unwrap(),
        )
        .unwrap()
    };
    let mut alice2 = restore(&alice, "alice");
    let mut bob2 = restore(&bob, "bob");
    drop(alice);
    drop(bob);

    // Joiner sends after restart, creator receives.
    let r2 = bob2.encrypt(b"b2 after restart").unwrap();
    assert_eq!(alice2.decrypt(&r2).unwrap(), b"b2 after restart");

    // Creator sends after restart, joiner receives.
    let c2 = alice2.encrypt(b"a2 after restart").unwrap();
    assert_eq!(bob2.decrypt(&c2).unwrap(), b"a2 after restart");
}

// Org groups use the moss peer-id as the credential identity (ADR 0004);
// these tests use short fake ids — identity is an opaque string here.
fn three_party() -> (MlsSessionCrypto, MlsSessionCrypto, MlsSessionCrypto) {
    let mut admin = MlsSessionCrypto::new("peer-admin").unwrap();
    admin.create_group().unwrap();
    let mut bob = MlsSessionCrypto::new("peer-bob").unwrap();
    let mut carol = MlsSessionCrypto::new("peer-carol").unwrap();
    let bob_kp = bob.key_package_bytes().unwrap();
    let outcome = admin.add_members(&[bob_kp.as_slice()]).unwrap();
    bob.join_welcome(&outcome.welcome_bytes, &outcome.tree_bytes)
        .unwrap();
    let carol_kp = carol.key_package_bytes().unwrap();
    let outcome = admin.add_members(&[carol_kp.as_slice()]).unwrap();
    bob.process_commit(&outcome.commit_bytes).unwrap();
    carol
        .join_welcome(&outcome.welcome_bytes, &outcome.tree_bytes)
        .unwrap();
    (admin, bob, carol)
}

#[test]
fn member_identities_lists_credentials() {
    let (admin, _bob, _carol) = three_party();
    let mut ids = admin.member_identities();
    ids.sort();
    assert_eq!(ids, vec!["peer-admin", "peer-bob", "peer-carol"]);
}

#[test]
fn remove_by_identity_kicks_and_advances_epoch() {
    let (mut admin, mut bob, mut carol) = three_party();
    let commit = admin.remove_members_by_identity("peer-bob").unwrap();
    carol.process_commit(&commit).unwrap();
    assert_eq!(admin.member_count(), 2);
    assert!(!admin.member_identities().contains(&"peer-bob".to_string()));

    // Post-kick traffic: carol still reads, bob cannot.
    let ct = admin.encrypt(b"after kick").unwrap();
    assert_eq!(carol.decrypt(&ct).unwrap(), b"after kick");
    assert!(bob.decrypt(&ct).is_err());
}

#[test]
fn remove_by_identity_errors_when_absent() {
    let (mut admin, _bob, _carol) = three_party();
    assert!(admin.remove_members_by_identity("peer-nobody").is_err());
}

#[test]
fn remove_by_identity_removes_all_duplicate_leaves() {
    // A rejoin can leave a stale leaf behind: two leaves, one identity.
    let (mut admin, mut bob_v1, mut carol) = three_party();
    let mut bob_v2 = MlsSessionCrypto::new("peer-bob").unwrap();
    let kp = bob_v2.key_package_bytes().unwrap();
    let outcome = admin.add_members(&[kp.as_slice()]).unwrap();
    bob_v1.process_commit(&outcome.commit_bytes).unwrap();
    carol.process_commit(&outcome.commit_bytes).unwrap();
    bob_v2
        .join_welcome(&outcome.welcome_bytes, &outcome.tree_bytes)
        .unwrap();
    assert_eq!(admin.member_count(), 4);

    let commit = admin.remove_members_by_identity("peer-bob").unwrap();
    carol.process_commit(&commit).unwrap();
    assert_eq!(admin.member_count(), 2);
    assert!(!admin.member_identities().contains(&"peer-bob".to_string()));

    let ct = admin.encrypt(b"both devices gone").unwrap();
    assert_eq!(carol.decrypt(&ct).unwrap(), b"both devices gone");
    assert!(bob_v1.decrypt(&ct).is_err());
    assert!(bob_v2.decrypt(&ct).is_err());
}

#[test]
fn replace_member_without_match_degrades_to_plain_add() {
    let (mut admin, mut bob, mut carol) = three_party();
    let mut dave = MlsSessionCrypto::new("peer-dave").unwrap();
    let kp = dave.key_package_bytes().unwrap();

    let outcome = admin.replace_member("peer-dave", &kp).unwrap();
    bob.process_commit(&outcome.commit_bytes).unwrap();
    carol.process_commit(&outcome.commit_bytes).unwrap();
    dave.join_welcome(&outcome.welcome_bytes, &outcome.tree_bytes)
        .unwrap();

    assert_eq!(admin.member_count(), 4);
    let ct = dave.encrypt(b"hello from dave").unwrap();
    assert_eq!(admin.decrypt(&ct).unwrap(), b"hello from dave");
}

#[test]
fn remove_by_identity_never_targets_own_leaf() {
    let (mut admin, _bob, _carol) = three_party();
    // Own identity matches only the committer's own leaf -> treated as
    // "no removable member", not a self-kick.
    assert!(admin.remove_members_by_identity("peer-admin").is_err());
}

#[test]
fn epoch_advances_and_commit_epoch_peeks() {
    let (mut admin, _bob, _carol) = three_party();
    let e0 = admin.epoch().unwrap();
    let mut dave = MlsSessionCrypto::new("peer-dave").unwrap();
    let kp = dave.key_package_bytes().unwrap();
    let outcome = admin.add_members(&[kp.as_slice()]).unwrap();
    // The commit was created AT e0 and advanced the group to e0+1.
    assert_eq!(
        MlsSessionCrypto::commit_epoch(&outcome.commit_bytes).unwrap(),
        e0
    );
    assert_eq!(admin.epoch().unwrap(), e0 + 1);
}

#[test]
fn commit_epoch_rejects_garbage() {
    assert!(MlsSessionCrypto::commit_epoch(b"not a commit").is_err());
}

#[test]
fn replace_member_swaps_device_in_one_commit() {
    let (mut admin, mut bob_old, mut carol) = three_party();
    // Same identity, fresh device/keys — same string as the roster entry.
    let mut bob_new = MlsSessionCrypto::new("peer-bob").unwrap();
    let kp = bob_new.key_package_bytes().unwrap();

    let outcome = admin.replace_member("peer-bob", &kp).unwrap();
    assert_eq!(
        outcome.tree_bytes,
        admin
            .group
            .as_ref()
            .unwrap()
            .export_ratchet_tree()
            .tls_serialize_detached()
            .unwrap()
    );
    carol.process_commit(&outcome.commit_bytes).unwrap();
    bob_new
        .join_welcome(&outcome.welcome_bytes, &outcome.tree_bytes)
        .unwrap();

    // Still exactly one peer-bob leaf; group size unchanged.
    assert_eq!(admin.member_count(), 3);
    let bobs = admin
        .member_identities()
        .into_iter()
        .filter(|id| id == "peer-bob")
        .count();
    assert_eq!(bobs, 1);

    // New device sends, everyone reads; old device is dead.
    let ct = bob_new.encrypt(b"new laptop").unwrap();
    assert_eq!(admin.decrypt(&ct).unwrap(), b"new laptop");
    let ct2 = admin.encrypt(b"welcome back").unwrap();
    assert!(bob_old.decrypt(&ct2).is_err());
}
