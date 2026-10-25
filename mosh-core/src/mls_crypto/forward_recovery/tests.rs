use super::*;

fn pair() -> (MlsSessionCrypto, MlsSessionCrypto) {
    let mut alice = MlsSessionCrypto::new("alice").unwrap();
    let mut bob = MlsSessionCrypto::new("bob").unwrap();
    alice.create_group().unwrap();
    let (welcome, tree) = alice.add_peer(&bob.key_package_bytes().unwrap()).unwrap();
    bob.join_welcome(&welcome, &tree).unwrap();
    (alice, bob)
}

fn skip(alice: &mut MlsSessionCrypto, count: u32) -> Vec<u8> {
    for _ in 0..count {
        alice.encrypt(b"lost control").unwrap();
    }
    alice.encrypt(b"current text").unwrap()
}

fn release_budget(crypto: &MlsSessionCrypto) {
    *crypto.forward_recovery.as_ref().unwrap().0.lock().unwrap() =
        Some(Instant::now() - RETRY_INTERVAL);
}

#[test]
fn recovered_state_restores_policy_and_survives_restart() {
    let (mut alice, mut bob) = pair();
    let configuration = MlsGroupJoinConfig::builder()
        .padding_size(17)
        .max_past_epochs(2)
        .number_of_resumption_psks(3)
        .use_ratchet_tree_extension(true)
        .sender_ratchet_configuration(SenderRatchetConfiguration::new(7, 1000))
        .build();
    bob.group
        .as_mut()
        .unwrap()
        .set_configuration(bob.provider.storage(), &configuration)
        .unwrap();
    let ciphertext = skip(&mut alice, 1250);
    assert!(
        bob.decrypt(&ciphertext).is_err(),
        "ordinary MLS owners keep their limit"
    );
    bob.enable_dm_forward_recovery();
    assert_eq!(bob.decrypt(&ciphertext).unwrap(), b"current text");
    assert_eq!(bob.group.as_ref().unwrap().configuration(), &configuration);
    assert!(
        bob.decrypt(&ciphertext).is_err(),
        "a replay must still be refused"
    );
    let mut restored = bob.receive_candidate().unwrap();
    let answer = restored.encrypt(b"after restart").unwrap();
    assert_eq!(alice.decrypt(&answer).unwrap(), b"after restart");
    let next = alice.encrypt(b"next").unwrap();
    assert_eq!(restored.decrypt(&next).unwrap(), b"next");
}

#[test]
fn forged_catch_up_preserves_state_and_throttles_repeated_work() {
    let (mut alice, mut bob) = pair();
    let ciphertext = skip(&mut alice, 1250);
    bob.enable_dm_forward_recovery();
    // Warm the ordinary failure path before asserting the additional retry's rollback.
    bob.forward_recovery = None;
    assert!(bob.decrypt(&ciphertext).is_err());
    bob.enable_dm_forward_recovery();
    let before = bob.snapshot();
    let signer = std::mem::replace(
        &mut alice.signer,
        SignatureKeyPair::new(SignatureScheme::ED25519).unwrap(),
    );
    let forged = alice.encrypt(b"forged sender").unwrap();
    alice.signer = signer;
    assert!(bob.decrypt(&forged).is_err());
    assert_eq!(bob.snapshot(), before);
    assert!(
        bob.decrypt(&ciphertext).is_err(),
        "a refused attempt consumes the budget"
    );
    release_budget(&bob);
    assert_eq!(bob.decrypt(&ciphertext).unwrap(), b"current text");
}

#[test]
fn refused_outer_proof_cannot_reset_the_catch_up_budget() {
    let (mut alice, mut bob) = pair();
    let ciphertext = skip(&mut alice, 1250);
    bob.enable_dm_forward_recovery();
    let before = bob.snapshot();
    assert!(bob
        .decrypt_checked(&ciphertext, |_, _| Err("wrong author".into()))
        .is_err());
    assert_eq!(bob.snapshot(), before);
    assert!(bob.decrypt_checked(&ciphertext, |_, _| Ok(())).is_err());
    release_budget(&bob);
    assert_eq!(
        bob.decrypt_checked(&ciphertext, |_, _| Ok(())).unwrap().0,
        b"current text"
    );
}

#[test]
fn catch_up_is_bounded_at_the_configured_ceiling() {
    let (mut alice, mut bob) = pair();
    let ciphertext = skip(&mut alice, MAX_FORWARD_RECOVERY);
    let mut beyond = bob.receive_candidate().unwrap();
    let too_far = alice.encrypt(b"beyond budget").unwrap();
    beyond.enable_dm_forward_recovery();
    let before = beyond.snapshot();
    assert!(beyond.decrypt(&too_far).is_err());
    assert_eq!(beyond.snapshot(), before);
    bob.enable_dm_forward_recovery();
    let started = Instant::now();
    assert_eq!(bob.decrypt(&ciphertext).unwrap(), b"current text");
    eprintln!("65,536-generation recovery: {:?}", started.elapsed());
}

#[test]
fn recovery_budget_uses_monotonic_time_without_sleeping() {
    let budget = ForwardRecovery::default();
    let now = Instant::now();
    assert!(budget.admit(now));
    assert!(!budget.admit(now));
    assert!(!budget.admit(now + RETRY_INTERVAL - Duration::from_millis(1)));
    assert!(budget.admit(now + RETRY_INTERVAL));
}
