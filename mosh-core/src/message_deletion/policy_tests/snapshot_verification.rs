use super::*;

fn snapshot(fixture: &Fixture, policy: &DeletionAuthority) -> MessageMetadata {
    super::super::snapshot::messages(&fixture.log, &fixture.transfer, &fixture.book, Some(policy))
        [0]
    .metadata
    .clone()
    .unwrap()
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
