use super::*;
use crate::message_deletion::{DeleteScope, DeletionRecord, DeletionStatus};

fn personal(f: &Fixture, key: &str) -> DeletionRecord {
    DeletionRecord {
        personal_correlation: None,
        context: "channel:general".into(),
        key: key.into(),
        scope: DeleteScope::ForMe,
        owner: f.runtime.identity.roster().user_id(),
        local_only: false,
        status: DeletionStatus::Confirmed,
        administrator: None,
        request: None,
        acknowledgement: None,
    }
}

#[test]
fn personal_deletion_pages_are_saved_before_being_acknowledged() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut f = Fixture::new();
    f.runtime.sync_deletions().unwrap();
    let request_id = f
        .runtime
        .deletion_pages
        .get(&f.peer.device().device_id)
        .unwrap()
        .request_id;
    let record = personal(&f, &"a".repeat(64));
    f.receive(NameMessage::DeletionBatch {
        records: vec![record.clone()],
        next: None,
        request_id,
    })
    .unwrap();
    assert_eq!(
        f.store.deletion_records("channel:general").unwrap(),
        vec![record.clone()]
    );
    f.restart();
    assert_eq!(
        f.store.deletion_records("channel:general").unwrap(),
        vec![record]
    );
}

#[test]
fn a_linked_peer_cannot_delete_for_a_different_account() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut f = Fixture::new();
    f.runtime.sync_deletions().unwrap();
    let request_id = f
        .runtime
        .deletion_pages
        .get(&f.peer.device().device_id)
        .unwrap()
        .request_id;
    let mut record = personal(&f, &"b".repeat(64));
    record.owner = "another account".into();
    assert!(f
        .receive(NameMessage::DeletionBatch {
            records: vec![record],
            next: None,
            request_id
        })
        .is_err());
    assert!(f
        .store
        .deletion_records("channel:general")
        .unwrap()
        .is_empty());
}

#[test]
fn stale_deletion_pages_cannot_complete_a_new_pull() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut f = Fixture::new();
    f.runtime.sync_deletions().unwrap();
    let old = f.runtime.deletion_pages[&f.peer.device().device_id].request_id;
    f.restart();
    f.runtime.sync_deletions().unwrap();
    let record = personal(&f, &"a".repeat(64));
    f.receive(NameMessage::DeletionBatch {
        records: vec![record],
        next: None,
        request_id: old,
    })
    .unwrap();
    assert!(f
        .store
        .deletion_records("channel:general")
        .unwrap()
        .is_empty());
    assert!(f
        .runtime
        .deletion_pages
        .contains_key(&f.peer.device().device_id));
}

#[test]
fn fragmented_deletion_pages_are_saved_only_after_complete_authenticated_reassembly() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut f = Fixture::new();
    f.runtime.sync_deletions().unwrap();
    let request_id = f.runtime.deletion_pages[&f.peer.device().device_id].request_id;
    let records: Vec<_> = (0..16)
        .map(|i| {
            let mut r = personal(&f, &format!("{i:064x}"));
            r.context = format!("channel:{}", "long".repeat(125));
            r
        })
        .collect();
    let context = records[0].context.clone();
    let message = NameMessage::DeletionBatch {
        records: records.clone(),
        next: None,
        request_id,
    };
    let bytes = serde_json::to_vec(&message).unwrap();
    let mut fragments = crate::message_deletion::fragment_buffer::split_bytes(&bytes).unwrap();
    let last = fragments.remove(0);
    for fragment in fragments.into_iter().rev() {
        f.receive(NameMessage::DeletionFragment { fragment })
            .unwrap();
    }
    assert!(f.store.deletion_records(&context).unwrap().is_empty());
    f.receive(NameMessage::DeletionFragment { fragment: last })
        .unwrap();
    assert_eq!(f.store.deletion_records(&context).unwrap(), records);
    f.restart();
    assert_eq!(f.store.deletion_records(&context).unwrap().len(), 16);
}
