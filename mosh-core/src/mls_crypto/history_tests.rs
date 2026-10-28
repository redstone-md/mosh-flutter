use super::*;

#[test]
fn refused_staged_receive_can_retry_without_consuming_the_live_ratchet() {
    let mut alice = MlsSessionCrypto::new("alice").unwrap();
    alice.create_group().unwrap();
    let mut bob = MlsSessionCrypto::new("bob").unwrap();
    let package = bob.key_package_bytes().unwrap();
    let (welcome, tree) = alice.add_peer(&package).unwrap();
    bob.join_welcome(&welcome, &tree).unwrap();
    let ciphertext = alice.encrypt(b"retain original accepted content").unwrap();
    let signer = alice.signer_public();

    let staged = bob
        .stage_decrypt_checked(&ciphertext, |body, actual| {
            assert_eq!(body, b"retain original accepted content");
            assert_eq!(actual, signer);
            Ok(())
        })
        .unwrap();
    assert_eq!(staged.body, b"retain original accepted content");
    drop(staged);

    let accepted = bob
        .stage_decrypt_checked(&ciphertext, |_, actual| {
            assert_eq!(actual, signer);
            Ok(())
        })
        .unwrap();
    assert_eq!(accepted.signer, signer);
    bob = accepted.next;
    assert!(bob.decrypt(&ciphertext).is_err());
    let next = alice.encrypt(b"live traffic still works").unwrap();
    assert_eq!(bob.decrypt(&next).unwrap(), b"live traffic still works");
}

#[test]
fn verified_history_context_survives_receiving_and_own_snapshot_restore() {
    let mut alice = MlsSessionCrypto::new("alice").unwrap();
    alice.create_group().unwrap();
    let mut bob = MlsSessionCrypto::new("bob").unwrap();
    let package = bob.key_package_bytes().unwrap();
    let (welcome, tree) = alice.add_peer(&package).unwrap();
    bob.join_welcome(&welcome, &tree).unwrap();

    let context = bob.history_context().unwrap();
    assert_eq!(context, alice.history_context().unwrap());
    assert_eq!(context.epoch, 1);
    assert_eq!(context.group_id, bob.group_id_bytes().unwrap());
    assert_eq!(context.hash.len(), 64);
    let ciphertext = alice
        .encrypt(b"context is independent of sender ratchets")
        .unwrap();
    assert_eq!(
        bob.decrypt(&ciphertext).unwrap(),
        b"context is independent of sender ratchets"
    );
    let restored = MlsSessionCrypto::restore(
        "bob",
        &bob.signer_public(),
        &bob.snapshot(),
        &bob.group_id_bytes().unwrap(),
    )
    .unwrap();
    assert_eq!(restored.history_context().unwrap(), context);
}

#[test]
fn encrypted_membership_replay_is_staged_on_the_recipients_own_branch() {
    let mut alice = MlsSessionCrypto::new("alice").unwrap();
    alice.create_group().unwrap();
    let mut bob = MlsSessionCrypto::new("bob").unwrap();
    let package = bob.key_package_bytes().unwrap();
    let (welcome, tree) = alice.add_peer(&package).unwrap();
    bob.join_welcome(&welcome, &tree).unwrap();
    let old_text = alice.encrypt(b"previous epoch remains usable").unwrap();
    let prior = bob.history_context().unwrap();
    let mut carol = MlsSessionCrypto::new("carol").unwrap();
    let package = carol.key_package_bytes().unwrap();
    let added = alice.add_members(&[&package]).unwrap();
    let wire = MlsMessageIn::tls_deserialize(&mut added.commit_bytes.as_slice()).unwrap();
    assert!(matches!(
        wire.extract(),
        MlsMessageBodyIn::PrivateMessage(_)
    ));

    let staged = bob.stage_membership(&added.commit_bytes, None).unwrap();
    assert_eq!(staged.prior, prior);
    assert_eq!(staged.context, alice.history_context().unwrap());
    assert_eq!(staged.author, alice.signer_public());
    assert!(!staged.removed);
    drop(staged);
    assert_eq!(bob.epoch(), Some(1));
    assert_eq!(
        bob.decrypt(&old_text).unwrap(),
        b"previous epoch remains usable"
    );

    let accepted = bob.stage_membership(&added.commit_bytes, None).unwrap();
    bob = accepted.next;
    assert_eq!(bob.epoch(), Some(2));
    assert_eq!(bob.member_count(), 3);
    let new_text = alice.encrypt(b"continued live traffic").unwrap();
    assert_eq!(bob.decrypt(&new_text).unwrap(), b"continued live traffic");
}

#[test]
fn refused_pinned_admission_preserves_the_joiners_original_key_package() {
    let mut alice = MlsSessionCrypto::new("alice").unwrap();
    alice.create_group().unwrap();
    let mut bob = MlsSessionCrypto::new("bob").unwrap();
    let package = bob.key_package_bytes().unwrap();
    let added = alice.add_members(&[&package]).unwrap();
    let stage = || {
        bob.stage_pinned_admission(
            &added.welcome_bytes,
            &added.tree_bytes,
            &alice.fingerprint(),
            Some(&alice.signer_public()),
            Some("alice"),
        )
        .unwrap()
    };
    let refused = stage();
    assert_eq!(refused.context, alice.history_context().unwrap());
    assert_eq!(refused.author, alice.signer_public());
    assert_eq!(refused.author_identity, "alice");
    drop(refused);
    assert!(!bob.is_ready());
    bob = stage().next;
    let ciphertext = alice
        .encrypt(b"admission still usable after refusal")
        .unwrap();
    assert_eq!(
        bob.decrypt(&ciphertext).unwrap(),
        b"admission still usable after refusal"
    );
}
