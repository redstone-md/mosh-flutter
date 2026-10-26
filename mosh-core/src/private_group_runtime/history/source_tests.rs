use super::*;
use crate::moss_ffi::MOSS_TEST_LOCK;
use crate::private_group_runtime::durability_tests::Fixture;

#[test]
fn a_frozen_erased_large_record_restarts_its_fragment_once_then_makes_progress() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let (record, sender) =
        super::super::import::tests::retained(&mut fixture, &"\u{0001}".repeat(4_000));
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    let scope = session.own_history_scope().unwrap();
    let frame = HistoryFrame {
        version: 1,
        conversation: session.deletions.context.clone(),
        mesh_id: session.mesh_id.clone(),
        channel: session.control_channel.clone(),
        sender_key: sender.peer_id,
        recipient_key: None,
        request_id: "12".repeat(16),
        round: 1,
        payload_b64: String::new(),
        signature: String::new(),
    };
    let (
        HistoryMessage::Offer {
            manifest,
            deletion_digest,
            ..
        },
        _,
    ) = session.history_answer(&frame, &scope, None, None).unwrap()
    else {
        panic!("expected native manifest");
    };
    let mut pull = HistoryPull {
        manifest,
        deletion_digest,
        offset: 0,
        fragment_offset: 0,
        journal: false,
        journal_after: None,
    };
    let (
        HistoryMessage::Page {
            fragment: Some(original),
            ..
        },
        _,
    ) = session
        .history_answer(&frame, &scope, Some(pull.clone()), None)
        .unwrap()
    else {
        panic!("expected bounded original fragment");
    };
    fixture
        .runtime
        .delete_messages(
            &fixture.id,
            std::slice::from_ref(&record.message_id),
            crate::message_deletion::DeleteScope::ForEveryone,
        )
        .unwrap();
    let session = fixture.runtime.groups.get_mut(&fixture.id).unwrap();
    pull.fragment_offset = crate::conversation::recovery::fragment::CHUNK;
    let (
        HistoryMessage::Page {
            fragment: Some(replaced),
            ..
        },
        reset,
    ) = session
        .history_answer(&frame, &scope, Some(pull.clone()), Some(&original.digest))
        .unwrap()
    else {
        panic!("expected bounded erased replacement");
    };
    assert!(reset);
    assert_eq!(replaced.offset, 0);
    assert_ne!(replaced.digest, original.digest);
    let (
        HistoryMessage::Page {
            fragment: Some(next),
            ..
        },
        reset,
    ) = session
        .history_answer(&frame, &scope, Some(pull), Some(&replaced.digest))
        .unwrap()
    else {
        panic!("expected erased continuation");
    };
    assert!(!reset);
    assert_eq!(next.offset, crate::conversation::recovery::fragment::CHUNK);
    assert_eq!(next.digest, replaced.digest);
}
