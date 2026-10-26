use super::*;
use crate::conversation::{
    history::StoredMessage,
    recovery::{HistoryClassification, HistoryEvidence},
};
use crate::test_temp_directory::TempDirectory;
use serde::{Deserialize, Serialize};
use std::sync::Arc;

#[derive(Debug, Serialize, Deserialize, PartialEq)]
struct Evidence {
    accepted: String,
}
#[derive(Clone, Serialize, Deserialize)]
struct Message {
    body: String,
}

#[test]
fn a_refused_own_snapshot_cannot_commit_history_evidence_or_continuation() {
    let directory = TempDirectory::new("atomic-history-evidence");
    let store =
        Arc::new(Persistence::open_with_dek(&directory.path().join("history"), [44; 32]).unwrap());
    let evidence = history_admission::EvidenceWrite {
        key: "group:test:acceptance:one".into(),
        bytes: serde_json::to_vec(&Evidence {
            accepted: "exact original".into(),
        })
        .unwrap(),
    };
    let row = StoredMessage {
        conversation_id: "group-test".into(),
        message_id: "one".into(),
        sent_at_ms: 1000,
        message: Message {
            body: "retained".into(),
        },
        attachment_manifest: None,
        preview_manifest: None,
        history_evidence: Some(HistoryEvidence {
            holder_key: "22".repeat(32),
            classification: HistoryClassification::OriginalOrigin,
            group: None,
        }),
    };
    let fault = store.refuse_group_snapshot_writes();
    let admit = || {
        store.commit_history_admission(
            GROUP_HISTORY,
            "group-test",
            HistoryAdmission {
                state: Some(("group-test", b"{}")),
                checkpoint: Some(("group:test:local", b"1")),
                own_snapshot: Some(b"own staged state"),
                evidence: std::slice::from_ref(&evidence),
                ..Default::default()
            },
            std::slice::from_ref(&row),
        )
    };
    assert!(admit().is_err());
    assert!(store
        .list_history_messages(GROUP_HISTORY, "group-test")
        .unwrap()
        .is_empty());
    assert!(store.list_conversations(GROUP_HISTORY).unwrap().is_empty());
    assert!(store
        .group_history_evidence::<Evidence>(&evidence.key)
        .unwrap()
        .is_none());
    assert!(store
        .recovery_state::<u64>("group:test:local")
        .unwrap()
        .is_none());
    drop(fault);
    admit().unwrap();
    assert_eq!(
        store
            .list_history_messages(GROUP_HISTORY, "group-test")
            .unwrap()
            .len(),
        1
    );
    assert_eq!(
        store
            .group_history_evidence::<Evidence>(&evidence.key)
            .unwrap()
            .unwrap()
            .accepted,
        "exact original"
    );
    assert_eq!(
        store.recovery_state::<u64>("group:test:local").unwrap(),
        Some(1)
    );
    let mut ordinary = row;
    ordinary.history_evidence = None;
    store
        .append_history_message(
            GROUP_HISTORY,
            "group-test",
            1000,
            "one",
            &serde_json::to_vec(&ordinary).unwrap(),
        )
        .unwrap();
    let saved: StoredMessage<Message> = serde_json::from_slice(
        &store
            .list_history_messages(GROUP_HISTORY, "group-test")
            .unwrap()[0],
    )
    .unwrap();
    assert!(
        saved.history_evidence.is_some(),
        "ordinary persistence retains accepted proof provenance"
    );
}
