use super::*;

#[test]
fn revoked_issuer_cannot_mint_a_new_group_deletion_certificate() {
    let (record, policy, reader) = delegation_fixture(false);
    let mut f = Fixture::new(&reader);
    assert!(f
        .context()
        .receive(
            DeletionMessage::State {
                records: vec![record],
                next: None,
            },
            &key(&reader),
            &policy,
            |b| Ok(sign(&reader, b))
        )
        .is_err());
    assert_eq!(f.log[0].body, "content");
    assert!(f.book.records.is_empty());
}

#[test]
fn active_roster_device_keeps_its_certificate_after_issuer_revocation() {
    let (record, policy, reader) = delegation_fixture(true);
    assert!(policy.validate(&record, &key(&reader)).is_ok());
}

fn delegation_fixture(active: bool) -> (DeletionRecord, DeletionAuthority, SigningKey) {
    let root = SigningKey::from_bytes(&[71; 32]);
    let linked = SigningKey::from_bytes(&[72; 32]);
    let reader = SigningKey::from_bytes(&[73; 32]);
    let f = Fixture::new(&root);
    let mut record = f.request(&linked, true);
    let request = record.request.as_mut().unwrap();
    request.ownership = Some(super::super::ownership::test_linked_proof(&root, &linked));
    request.signature = sign(&linked, &request.input().unwrap());
    let mut policy = authority(&reader, &linked);
    policy.admins.insert(key(&linked));
    policy.own.revoked.insert(key(&root));
    policy.own.accounts.insert(key(&root), key(&root));
    if active {
        policy.own.accounts.insert(key(&linked), key(&root));
    }
    (record, policy, reader)
}
