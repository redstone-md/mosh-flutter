use super::*;

#[test]
fn missing_account_certificate_does_not_make_own_messages_incoming() {
    let author = SigningKey::from_bytes(&[31; 32]);
    let reader = SigningKey::from_bytes(&[32; 32]);
    let f = Fixture::new(&author);
    let mut policy = authority(&author, &reader);
    policy.local.ownership = None;
    let messages =
        crate::message_deletion::snapshot::messages(&f.log, &f.transfer, &f.book, Some(&policy));
    let metadata = messages[0].metadata.as_ref().unwrap();
    assert_eq!(metadata.is_own, Some(true));
    assert!(!metadata.can_delete_for_everyone);
}

#[test]
fn a_receiver_waiting_for_its_certificate_does_not_echo_pull_requests() {
    let author = SigningKey::from_bytes(&[31; 32]);
    let reader = SigningKey::from_bytes(&[32; 32]);
    let mut f = Fixture::new(&author);
    let mut policy = authority(&reader, &author);
    let ownership = policy.local.ownership.take();
    let request = DeletionMessage::Request {
        after: None,
        digest: Some("different journal".into()),
    };
    let replies = f
        .context()
        .receive(request.clone(), &key(&author), &policy, |bytes| {
            Ok(sign(&reader, bytes))
        })
        .unwrap();
    assert!(matches!(&replies[..], [DeletionMessage::State { .. }]));
    policy.local.ownership = ownership;
    let replies = f
        .context()
        .receive(request, &key(&author), &policy, |bytes| {
            Ok(sign(&reader, bytes))
        })
        .unwrap();
    assert!(matches!(
        &replies[..],
        [
            DeletionMessage::State { .. },
            DeletionMessage::Request { .. }
        ]
    ));
}
