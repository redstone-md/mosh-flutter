use super::*;

fn snapshot(fixture: &Fixture, policy: &DeletionAuthority) -> MessageMetadata {
    super::super::snapshot::messages(&fixture.log, &fixture.transfer, &fixture.book, Some(policy))
        [0]
    .metadata
    .clone()
    .unwrap()
}

#[test]
fn a_history_snapshot_checks_its_local_actor_once_and_preserves_complete_rows() {
    let author = SigningKey::generate(&mut rand::rngs::OsRng);
    let mut fixture = Fixture::new(&author);
    for index in 1..16 {
        let id = format!("message-{index}");
        let mut message = TestMessage::new("same display name", "content")
            .with_id(&id)
            .at(index);
        message.metadata = Some(MessageMetadata {
            origin: Some(MessageOrigin::sign(ROOM, &id, b"content", &author, None).unwrap()),
            ..Default::default()
        });
        fixture.log.push(message);
    }
    let policy = authority(&author, &author);
    let expected: Vec<_> = fixture
        .log
        .iter()
        .cloned()
        .map(|mut message| {
            let metadata = message.metadata.as_mut().unwrap();
            metadata.can_delete_for_everyone = true;
            metadata.is_own = Some(true);
            message
        })
        .collect();
    let count = super::super::ownership::test_revocation_count;
    let before = count();
    let actual = super::super::snapshot::messages(
        &fixture.log,
        &fixture.transfer,
        &fixture.book,
        Some(&policy),
    );
    assert_eq!(actual, expected);
    assert_eq!(
        count() - before,
        1,
        "one immutable authority must not be revalidated per history row"
    );
}

#[test]
fn unavailable_deletion_storage_does_not_check_an_unused_local_actor() {
    let author = SigningKey::generate(&mut rand::rngs::OsRng);
    let mut fixture = Fixture::new(&author);
    fixture.book.store = None;
    let policy = authority(&author, &author);
    let count = super::super::ownership::test_revocation_count;
    let before = count();
    let metadata = snapshot(&fixture, &policy);
    assert!(!metadata.can_delete_for_everyone);
    assert_eq!(metadata.is_own, Some(true));
    assert_eq!(count(), before);
}

#[test]
fn unchanged_history_snapshots_do_not_repeat_signature_verification() {
    let author = SigningKey::generate(&mut rand::rngs::OsRng);
    let reader = SigningKey::generate(&mut rand::rngs::OsRng);
    let fixture = Fixture::new(&author);
    let policy = authority(&reader, &author);
    let expected = snapshot(&fixture, &policy);
    assert!(expected.can_delete_for_everyone);
    let before = super::super::verification::test_count();
    for _ in 0..20 {
        assert_eq!(snapshot(&fixture, &policy), expected);
    }
    assert_eq!(
        super::super::verification::test_count(),
        before,
        "unchanged UI polls must reuse successful cryptographic checks"
    );
}

#[test]
fn verified_history_does_not_preserve_lost_permissions() {
    let author = SigningKey::generate(&mut rand::rngs::OsRng);
    let reader = SigningKey::generate(&mut rand::rngs::OsRng);
    let fixture = Fixture::new(&author);
    let mut policy = authority(&reader, &author);
    assert!(snapshot(&fixture, &policy).can_delete_for_everyone);
    policy.admins.clear();
    assert!(!snapshot(&fixture, &policy).can_delete_for_everyone);
    policy.admins.insert(key(&reader));
    policy.own.revoked.insert(key(&reader));
    assert!(!snapshot(&fixture, &policy).can_delete_for_everyone);
    policy.own.revoked.clear();
    policy.members.remove(&key(&reader));
    assert!(!snapshot(&fixture, &policy).can_delete_for_everyone);
}

#[test]
fn changed_history_proofs_are_verified_after_a_successful_snapshot() {
    let author = SigningKey::generate(&mut rand::rngs::OsRng);
    let reader = SigningKey::generate(&mut rand::rngs::OsRng);
    let mut fixture = Fixture::new(&author);
    let policy = authority(&reader, &author);
    let original = fixture.log[0].clone();
    assert!(snapshot(&fixture, &policy).can_delete_for_everyone);
    for change in 0..6 {
        let mut message = original.clone();
        let origin = message.metadata.as_mut().unwrap().origin.as_mut().unwrap();
        match change {
            0 => origin.conversation.push('x'),
            1 => origin.id.push('x'),
            2 => origin.content_hash = "0".repeat(64),
            3 => origin.author = key(&reader),
            4 => origin.signature = "0".repeat(128),
            _ => origin.ownership = Some(super::super::ownership::test_proof(&reader)),
        }
        fixture.log.replace(0, message);
        assert!(!snapshot(&fixture, &policy).can_delete_for_everyone);
    }
    fixture.log.replace(0, original);
    assert!(snapshot(&fixture, &policy).can_delete_for_everyone);
}

#[test]
fn unchanged_linked_history_snapshots_do_not_repeat_delegation_verification() {
    let issuer = SigningKey::generate(&mut rand::rngs::OsRng);
    let author = SigningKey::generate(&mut rand::rngs::OsRng);
    let reader = SigningKey::generate(&mut rand::rngs::OsRng);
    let fixture = Fixture::new(&author);
    let mut policy = authority(&reader, &author);
    policy.local.ownership = Some(super::super::ownership::test_linked_proof(&issuer, &reader));
    let expected = snapshot(&fixture, &policy);
    assert!(expected.can_delete_for_everyone);
    let count = crate::device_link::account_certificate::test_verification_count;
    let before = count();
    for _ in 0..20 {
        assert_eq!(snapshot(&fixture, &policy), expected);
    }
    assert_eq!(
        count(),
        before,
        "unchanged history must reuse verified delegations"
    );
}

#[test]
fn cached_linked_history_proofs_still_enforce_issuer_revocation() {
    let issuer = SigningKey::generate(&mut rand::rngs::OsRng);
    let author = SigningKey::generate(&mut rand::rngs::OsRng);
    let reader = SigningKey::generate(&mut rand::rngs::OsRng);
    let fixture = Fixture::new(&author);
    let mut policy = authority(&reader, &author);
    policy.local.ownership = Some(super::super::ownership::test_linked_proof(&issuer, &reader));
    assert!(snapshot(&fixture, &policy).can_delete_for_everyone);
    policy.own.revoked.insert(key(&issuer));
    assert!(!snapshot(&fixture, &policy).can_delete_for_everyone);
    policy.own.revoked.clear();
    assert!(snapshot(&fixture, &policy).can_delete_for_everyone);
    policy.members.remove(&key(&reader));
    assert!(!snapshot(&fixture, &policy).can_delete_for_everyone);
}
