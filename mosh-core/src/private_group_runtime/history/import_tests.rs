use super::*;
use crate::moss_ffi::MOSS_TEST_LOCK;
use crate::private_group_runtime::durability_tests::Fixture;

pub(in crate::private_group_runtime::history) fn retained(
    fixture: &mut Fixture,
    body: &str,
) -> (GroupRecord, crate::sender_auth::VerifiedSender) {
    fixture.runtime.send(&fixture.id, body.into()).unwrap();
    let row = fixture
        .store
        .list_group_messages(&fixture.id)
        .unwrap()
        .pop()
        .unwrap();
    let row: StoredMessage<GroupMessage> = serde_json::from_slice(&row).unwrap();
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    let scope = session.own_history_scope().unwrap();
    let sender = scope.membership.verify_current(session).unwrap();
    let record = session
        .retained_history_record(&row, &scope, &sender.peer_id)
        .unwrap();
    (record, sender)
}

#[test]
fn changed_origin_interval_recipient_or_head_cannot_import_a_signed_group_record() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let (record, sender) = retained(&mut fixture, "unaltered original text");
    let original = serde_json::to_value(&record).unwrap();
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    record.verify(session, &sender).unwrap();
    let attacks = [
        ("/body", serde_json::json!("substituted plaintext")),
        ("/acceptance/receipt", serde_json::Value::Null),
        (
            "/acceptance/context/hash",
            serde_json::json!("00".repeat(32)),
        ),
        (
            "/vouch/recipient_moss_key",
            serde_json::json!("11".repeat(32)),
        ),
        (
            "/vouch/recipient_entitled_admission",
            serde_json::json!({"commit_v1":"22".repeat(32)}),
        ),
        (
            "/vouch/holder_current_head/context/hash",
            serde_json::json!("33".repeat(32)),
        ),
        (
            "/author_checkpoint/canonical_reference",
            serde_json::json!({"genesis_v1":"44".repeat(32)}),
        ),
    ];
    for (path, value) in attacks {
        let mut forged = original.clone();
        *forged.pointer_mut(path).unwrap() = value;
        let forged: GroupRecord = serde_json::from_value(forged).unwrap();
        assert!(
            forged.verify(session, &sender).is_err(),
            "accepted changed {path}"
        );
    }
    assert_eq!(session.messages.len(), 1);
}

#[test]
fn erased_slot_discards_partial_bytes_and_requires_the_verified_original_tombstone() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let (original, sender) = retained(&mut fixture, &"\u{0001}".repeat(4_000));
    let bytes = serde_json::to_vec(&original).unwrap();
    let mut next = Checkpoint::default();
    let mut records = Vec::new();
    assemble_records(
        &mut next,
        &mut records,
        Some(crate::conversation::recovery::fragment::fragment(&bytes, 0).unwrap()),
    )
    .unwrap();
    assert!(next.partial.is_some());
    fixture
        .runtime
        .delete_messages(
            &fixture.id,
            std::slice::from_ref(&original.message_id),
            crate::message_deletion::DeleteScope::ForEveryone,
        )
        .unwrap();
    let row = fixture
        .store
        .list_group_messages(&fixture.id)
        .unwrap()
        .pop()
        .unwrap();
    let row: StoredMessage<GroupMessage> = serde_json::from_slice(&row).unwrap();
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    let scope = session.own_history_scope().unwrap();
    let erased = session
        .retained_history_record(&row, &scope, &sender.peer_id)
        .unwrap();
    assert_eq!(
        erased.acceptance.record_hash,
        original.acceptance.record_hash
    );
    assert!(erased.body.is_empty() && erased.offer.is_none());
    let mut replacement = vec![erased.clone()];
    assemble_records(&mut next, &mut replacement, None).unwrap();
    assert!(next.partial.is_none());
    erased.verify(session, &sender).unwrap();
    let mut forged = serde_json::to_value(&erased).unwrap();
    forged["erased"]["deletion_key"] = "55".repeat(32).into();
    let forged = serde_json::from_value(forged).unwrap();
    assert!(session.imported_history_row(forged, &sender).is_err());
    let (row, _) = session.imported_history_row(erased, &sender).unwrap();
    assert!(row.message.body.is_empty());
    assert!(row.message.metadata.unwrap().deletion.is_some());
}
