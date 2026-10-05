use super::*;

#[test]
fn unknown_author_deletion_is_freshly_acknowledged_after_earlier_recipient_leaves() {
    let author = SigningKey::from_bytes(&[31; 32]);
    let reader = SigningKey::from_bytes(&[32; 32]);
    let departed = SigningKey::from_bytes(&[33; 32]);
    let mut f = Fixture::new(&author);
    let record = confirmed(&f.request(&author, false), &departed);
    let mut policy = authority(&reader, &author);
    policy.admins.clear();
    let replies = f
        .context()
        .receive(
            DeletionMessage::State {
                records: vec![record],
                next: None,
            },
            &key(&author),
            &policy,
            |bytes| Ok(sign(&reader, bytes)),
        )
        .unwrap();
    assert_eq!(f.log[0].body, "");
    assert!(
        matches!(&replies[..], [DeletionMessage::Ack { acknowledgement, .. }]
        if acknowledgement.actor == key(&reader))
    );
    f.book.reload().unwrap();
    assert_eq!(f.book.accepted.len(), 1);
}

#[test]
fn personal_erasure_matches_native_and_authenticated_legacy_copies_in_both_directions() {
    let author = SigningKey::from_bytes(&[31; 32]);
    for native_source in [false, true] {
        let mut source = Fixture::new(&author);
        let mut destination = Fixture::new(&author);
        let legacy = if native_source {
            &mut destination
        } else {
            &mut source
        };
        let message = legacy.log.find_mut("message").unwrap();
        message.metadata = None;
        crate::message_deletion::target::correlate_history_text(ROOM, message).unwrap();
        crate::message_deletion::delete_for_me(&mut source.context(), &["message".into()], None)
            .unwrap();
        let records = source
            .book
            .store
            .as_ref()
            .unwrap()
            .account_deletions("local")
            .unwrap();
        destination
            .book
            .store
            .as_ref()
            .unwrap()
            .save_account_deletions("local", &records)
            .unwrap();
        crate::message_deletion::apply(&mut destination.context()).unwrap();
        assert!(
            destination.log.visible().is_empty(),
            "native source: {native_source}"
        );
        assert_eq!(destination.log[0].body, "");
    }
}

#[test]
fn personal_correlation_survives_a_shared_placeholder_without_granting_shared_authority() {
    let author = SigningKey::from_bytes(&[31; 32]);
    let mut source = Fixture::new(&author);
    let mut legacy = Fixture::new(&author);
    let message = legacy.log.find_mut("message").unwrap();
    message.metadata = None;
    crate::message_deletion::correlate_history_text(ROOM, message).unwrap();
    let policy = authority(&author, &author);
    shared::admit(
        &mut source.context(),
        &["message".into()],
        &policy.local,
        |_| Some(false),
        |bytes| Ok(sign(&author, bytes)),
    )
    .unwrap();
    let records = source
        .book
        .store
        .as_ref()
        .unwrap()
        .account_deletions("local")
        .unwrap();
    legacy
        .book
        .store
        .as_ref()
        .unwrap()
        .save_account_deletions("local", &records)
        .unwrap();
    crate::message_deletion::apply(&mut legacy.context()).unwrap();
    assert_eq!(legacy.log[0].body, "content");
    crate::message_deletion::delete_for_me(&mut source.context(), &["message".into()], None)
        .unwrap();
    let records = source
        .book
        .store
        .as_ref()
        .unwrap()
        .account_deletions("local")
        .unwrap();
    legacy
        .book
        .store
        .as_ref()
        .unwrap()
        .save_account_deletions("local", &records)
        .unwrap();
    crate::message_deletion::apply(&mut legacy.context()).unwrap();
    assert!(legacy.log.visible().is_empty());
}

#[test]
fn an_imported_unchecked_receipt_cannot_become_native_acceptance_without_a_fresh_receipt() {
    let author = SigningKey::from_bytes(&[31; 32]);
    let absent = SigningKey::from_bytes(&[32; 32]);
    let mut f = Fixture::new(&author);
    let record = confirmed(&f.request(&author, false), &absent);
    f.book
        .store
        .as_ref()
        .unwrap()
        .save_account_deletions("local", std::slice::from_ref(&record))
        .unwrap();
    f.book.reload().unwrap();
    let mut policy = authority(&author, &author);
    policy.admins.clear();
    let replies = f
        .context()
        .receive(
            DeletionMessage::State {
                records: vec![record],
                next: None,
            },
            &key(&author),
            &policy,
            |bytes| Ok(sign(&author, bytes)),
        )
        .unwrap();
    assert!(replies.is_empty());
    f.book.reload().unwrap();
    assert!(f.book.accepted.is_empty());
}

#[test]
fn a_current_admin_receipt_recovers_moderation_without_that_admin_forwarding_it() {
    let old = SigningKey::from_bytes(&[31; 32]);
    let reader = SigningKey::from_bytes(&[32; 32]);
    let forwarder = SigningKey::from_bytes(&[33; 32]);
    let current = SigningKey::from_bytes(&[34; 32]);
    let mut f = Fixture::new(&reader);
    let record = confirmed(&f.request(&old, true), &current);
    let mut policy = authority(&reader, &old);
    policy.admins = [key(&current)].into();
    policy.members.remove(&key(&old));
    policy.members.extend([key(&forwarder), key(&current)]);
    f.context()
        .receive(
            DeletionMessage::State {
                records: vec![record],
                next: None,
            },
            &key(&forwarder),
            &policy,
            |bytes| Ok(sign(&reader, bytes)),
        )
        .unwrap();
    assert_eq!(f.log[0].body, "");
    f.book.reload().unwrap();
    assert_eq!(f.book.accepted.len(), 1);
}

#[test]
fn a_departed_author_and_member_cannot_confirm_a_new_deletion() {
    let author = SigningKey::from_bytes(&[31; 32]);
    let reader = SigningKey::from_bytes(&[32; 32]);
    let member = SigningKey::from_bytes(&[33; 32]);
    let mut f = Fixture::new(&author);
    let record = confirmed(&f.request(&author, false), &member);
    let mut policy = authority(&reader, &author);
    policy.admins.clear();
    policy.members.remove(&key(&author));
    policy.members.insert(key(&member));
    assert!(f
        .context()
        .receive(
            DeletionMessage::State {
                records: vec![record],
                next: None,
            },
            &key(&member),
            &policy,
            |bytes| Ok(sign(&reader, bytes)),
        )
        .is_err());
    assert_eq!(f.log[0].body, "content");
    assert!(f.book.records.is_empty());
}

#[test]
fn an_unknown_confirmation_cannot_bypass_the_current_epoch() {
    let author = SigningKey::from_bytes(&[31; 32]);
    let reader = SigningKey::from_bytes(&[32; 32]);
    let mut f = Fixture::new(&author);
    let mut pending = f.request(&author, false);
    let request = pending.request.as_mut().unwrap();
    request.epoch = 1;
    request.signature = sign(&author, &request.input().unwrap());
    let record = confirmed(&pending, &reader);
    let policy = authority(&reader, &author);
    assert!(f
        .context()
        .receive(
            DeletionMessage::State {
                records: vec![record],
                next: None,
            },
            &key(&author),
            &policy,
            |bytes| Ok(sign(&reader, bytes)),
        )
        .is_err());
    assert_eq!(f.log[0].body, "content");
    assert!(f.book.records.is_empty());
}

#[test]
fn author_departure_refuses_a_late_receipt_and_retains_personal_erasure() {
    let author = SigningKey::from_bytes(&[31; 32]);
    let reader = SigningKey::from_bytes(&[32; 32]);
    let mut f = Fixture::new(&author);
    let mut policy = authority(&author, &reader);
    shared::admit(
        &mut f.context(),
        &["message".into()],
        &policy.local,
        |_| Some(false),
        |bytes| Ok(sign(&author, bytes)),
    )
    .unwrap();
    let record = f.book.records.values().next().unwrap().clone();
    let receipt = confirmed(&record, &reader).acknowledgement.unwrap();
    policy.members.remove(&key(&author));
    assert!(f
        .context()
        .receive(
            DeletionMessage::Ack {
                key: record.key,
                acknowledgement: receipt,
            },
            &key(&reader),
            &policy,
            |bytes| Ok(sign(&author, bytes)),
        )
        .is_err());
    f.context().reconcile(&policy, false).unwrap();
    assert!(f.log.visible().is_empty());
    assert!(f.book.accepted.is_empty());
    assert_eq!(f.book.summary().unwrap().rejected_count, 1);
}
