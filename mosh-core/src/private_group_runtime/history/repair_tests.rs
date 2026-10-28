use super::*;
use crate::moss_ffi::MOSS_TEST_LOCK;
#[path = "repair_fixture.rs"]
mod fixture;
use fixture::Original;

#[test]
fn repair_retains_local_ownership_and_receipt_and_storage_refusal_is_atomic() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let mut original = Original::new();
    original.damage();
    original
        .fixture
        .store
        .save_background_intent(false, true)
        .unwrap();
    let session = original
        .fixture
        .runtime
        .groups
        .get_mut(&original.fixture.id)
        .unwrap();
    original.record.verify(session, &original.sender).unwrap();
    let (row, evidence) = session
        .imported_history_row(original.record.clone(), &original.sender)
        .unwrap();
    assert_eq!(row.message.metadata, original.row.message.metadata);
    assert_eq!(
        serde_json::to_value(&row.history_evidence).unwrap(),
        serde_json::to_value(&original.row.history_evidence).unwrap()
    );
    assert!(evidence.is_empty());
    let next = session.recovery.checkpoint.clone();
    let fault = original.fixture.store.refuse_message_writes(GROUP_HISTORY);
    assert!(original
        .session()
        .save_history(next.clone(), std::slice::from_ref(&row), &[], &[])
        .is_err());
    drop(fault);
    assert!(original.saved().preview_manifest.is_none());
    original
        .session()
        .save_history(next, &[row], &[], &[])
        .unwrap();
    assert!(original.saved().preview_manifest.is_some());
    assert!(original
        .fixture
        .store
        .pending_background_notifications(16)
        .unwrap()
        .is_empty());
}

#[test]
fn changed_remote_proof_offer_or_author_cannot_repair() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let mut original = Original::new();
    original.damage();
    let value = serde_json::to_value(&original.record).unwrap();
    for (path, replacement) in [
        (
            "/acceptance/record_hash",
            serde_json::json!("00".repeat(32)),
        ),
        (
            "/acceptance/original_author_mls_key",
            serde_json::json!("11".repeat(32)),
        ),
        (
            "/acceptance/original_sender_proof_b64",
            serde_json::json!("invalid"),
        ),
        (
            "/acceptance/receipt/mls_signature",
            serde_json::json!("00".repeat(64)),
        ),
        (
            "/offer/preview_manifest/key_b64",
            serde_json::json!(encode(&[9; 32])),
        ),
        ("/sent_at_ms", serde_json::json!(0)),
    ] {
        let mut forged = value.clone();
        *forged.pointer_mut(path).unwrap() = replacement;
        let forged: GroupRecord = serde_json::from_value(forged).unwrap();
        let session = original
            .fixture
            .runtime
            .groups
            .get_mut(&original.fixture.id)
            .unwrap();
        assert!(
            forged.verify(session, &original.sender).is_err(),
            "accepted changed {path}"
        );
        assert!(original.saved().preview_manifest.is_none());
    }
}

#[test]
fn a_conflicting_occurrence_or_another_holder_cannot_repair() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let mut original = Original::new();
    original.damage();
    let mut conflicting = original.record.clone();
    conflicting.acceptance.record_hash = "22".repeat(32);
    let session = original
        .fixture
        .runtime
        .groups
        .get_mut(&original.fixture.id)
        .unwrap();
    assert!(session
        .imported_history_row(conflicting, &original.sender)
        .is_err());
    let stranger = crate::sender_auth::VerifiedSender {
        peer_id: "33".repeat(32),
        mls_signer: vec![4; 32],
        payload: Vec::new(),
    };
    assert!(original.record.verify(session, &stranger).is_err());
}

#[test]
fn personal_and_global_erasure_never_restore_an_old_offer() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    for scope in [
        crate::message_deletion::DeleteScope::ForMe,
        crate::message_deletion::DeleteScope::ForEveryone,
    ] {
        let mut original = Original::new();
        original.damage();
        original
            .fixture
            .runtime
            .delete_messages(
                &original.fixture.id,
                std::slice::from_ref(&original.row.message_id),
                scope,
            )
            .unwrap();
        let session = original
            .fixture
            .runtime
            .groups
            .get_mut(&original.fixture.id)
            .unwrap();
        original.record.verify(session, &original.sender).unwrap();
        let (row, _) = session
            .imported_history_row(original.record.clone(), &original.sender)
            .unwrap();
        assert!(row.attachment_manifest.is_none() && row.preview_manifest.is_none());
        assert_eq!(
            row.message
                .metadata
                .as_ref()
                .unwrap()
                .deletion
                .as_ref()
                .unwrap()
                .scope,
            scope
        );
        session
            .save_history(session.recovery.checkpoint.clone(), &[row], &[], &[])
            .unwrap();
        assert!(original.saved().preview_manifest.is_none());
    }
}

#[test]
fn damaged_local_acceptance_cannot_replace_the_protected_occurrence() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let mut original = Original::new();
    original.damage();
    let mut accepted = original.record.acceptance.clone();
    accepted.record_hash = "44".repeat(32);
    accepted.receipt =
        super::super::receipts::AcceptanceEvidenceV1::native(original.session(), &accepted)
            .unwrap();
    let write = EvidenceWrite {
        key: native_acceptance_key(&original.fixture.id, &original.row.message_id),
        bytes: serde_json::to_vec(&accepted).unwrap(),
    };
    original
        .fixture
        .store
        .commit_history_admission::<GroupMessage>(
            GROUP_HISTORY,
            &original.fixture.id,
            HistoryAdmission {
                evidence: &[write],
                ..Default::default()
            },
            &[],
        )
        .unwrap();
    let session = original.session();
    session.recovery.occurrences_ready = false;
    assert!(session
        .save_history(session.recovery.checkpoint.clone(), &[], &[], &[])
        .is_err());
    assert!(original.saved().preview_manifest.is_none());
}

#[test]
fn first_acceptance_preserves_an_identical_verified_offer_without_reissuing_provenance() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let original = Original::new();
    let mut accepted = original.record.acceptance.clone();
    accepted.offer = original.record.offer.clone();
    let before = serde_json::to_value(&accepted).unwrap();
    let writes = accepted
        .first_write(
            &original.fixture.store,
            native_acceptance_key(&original.fixture.id, &original.row.message_id),
            false,
            &original.fixture.id,
        )
        .unwrap();
    assert!(writes.is_empty());
    assert!(accepted.offer.as_ref().unwrap().preview_manifest.is_some());
    assert_eq!(serde_json::to_value(accepted).unwrap(), before);
}

#[test]
fn repairing_an_incoming_offer_keeps_its_acknowledged_notification_and_local_state() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let mut original = Original::incoming();
    assert_eq!(
        original.row.message.metadata.as_ref().unwrap().is_own,
        Some(false)
    );
    let notices = original
        .fixture
        .store
        .pending_background_notifications(16)
        .unwrap();
    assert_eq!(notices.len(), 1);
    original
        .fixture
        .store
        .ack_background_notification(&notices[0].id, notices[0].revision)
        .unwrap();
    original.damage();
    let session = original
        .fixture
        .runtime
        .groups
        .get_mut(&original.fixture.id)
        .unwrap();
    original.record.verify(session, &original.sender).unwrap();
    let (row, evidence) = session
        .imported_history_row(original.record.clone(), &original.sender)
        .unwrap();
    assert_eq!(row.message.metadata, original.row.message.metadata);
    assert_eq!(
        serde_json::to_value(&row.history_evidence).unwrap(),
        serde_json::to_value(&original.row.history_evidence).unwrap()
    );
    session
        .save_history(session.recovery.checkpoint.clone(), &[row], &evidence, &[])
        .unwrap();
    assert!(original.saved().preview_manifest.is_some());
    assert!(original
        .fixture
        .store
        .pending_background_notifications(16)
        .unwrap()
        .is_empty());
}

#[test]
fn repair_does_not_replace_other_damaged_local_identity_or_content() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let mut original = Original::new();
    original.damage();
    let value = serde_json::to_value(original.saved()).unwrap();
    let record = original.record.clone();
    for (path, replacement) in [
        ("/conversation_id", serde_json::json!("another group")),
        ("/sent_at_ms", serde_json::json!(0)),
        ("/message/from_device", serde_json::json!("another author")),
        (
            "/message/from_fingerprint",
            serde_json::json!("55".repeat(32)),
        ),
        ("/message/body", serde_json::json!("substituted content")),
        (
            "/message/attachment/file_name",
            serde_json::json!("changed.jpg"),
        ),
    ] {
        let mut damaged = value.clone();
        *damaged.pointer_mut(path).unwrap() = replacement;
        let row = serde_json::from_value(damaged).unwrap();
        assert!(
            original
                .session()
                .retained_or_repaired_row(row, &record)
                .is_err(),
            "accepted changed {path}"
        );
    }
}

#[test]
fn an_empty_holder_cannot_complete_history_while_a_protected_preview_is_missing() {
    use crate::conversation::recovery::{coordinator::Coordinator, HistorySyncState};
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let mut original = Original::new();
    original.damage();
    let session = original.session();
    session.recovery.occurrences_ready = false;
    session
        .save_history(session.recovery.checkpoint.clone(), &[], &[], &[])
        .unwrap();
    assert_eq!(
        session.history_state().unwrap().state,
        HistorySyncState::WaitingForSource
    );
    session.recovery.checkpoint.source = Some("authorized-empty-holder".into());
    let mut next = session.recovery.checkpoint.clone();
    next.progress
        .advance(&"00".repeat(32), 0, 0, false)
        .unwrap();
    Coordinator::finished(&mut next, "authorized-empty-holder");
    let observations = next.observed.clone();
    session.save_history(next, &[], &[], &[]).unwrap();
    assert_eq!(
        session.history_state().unwrap().state,
        HistorySyncState::WaitingForSource
    );
    assert_eq!(session.recovery.checkpoint.observed, observations);
    assert!(original.saved().preview_manifest.is_none());
}
