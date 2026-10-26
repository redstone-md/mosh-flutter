use super::*;
use crate::api::conversation::BridgeConversationKind;
use crate::attachment_runtime::{AttachmentRuntime, ChunkRequest, OutgoingAttachment, CHUNK_SIZE};
use crate::test_temp_directory::TempDirectory;
use std::sync::Arc;

fn target() -> BridgeConversationRef {
    BridgeConversationRef {
        kind: BridgeConversationKind::Dm,
        id: "private-conversation".into(),
    }
}

fn manifest() -> (AttachmentRuntime, AttachmentManifest) {
    let mut runtime = AttachmentRuntime::new();
    let manifest = runtime
        .prepare_outgoing(OutgoingAttachment {
            attachment_id: "original-attachment".into(),
            file_name: "private-name.bin".into(),
            mime: "application/octet-stream".into(),
            from_fingerprint: "authenticated-sender".into(),
            bytes: vec![71; CHUNK_SIZE as usize * 2],
            thumbnail_b64: None,
            voice: None,
        })
        .unwrap();
    (runtime, manifest)
}

#[test]
fn durable_admission_and_only_saved_chunks_survive_restart_without_auto_execution() {
    let directory = TempDirectory::new("transfer-checkpoint-restart");
    let path = directory.path().join("history.redb");
    let store = Persistence::open_with_dek(&path, [44; 32]).unwrap();
    let (mut sender, manifest) = manifest();
    let admission = store
        .prepare_user_transfer(
            target(),
            Direction::Download,
            Some(manifest.attachment_id.clone()),
            manifest.total_size,
        )
        .unwrap();
    store
        .bind_user_transfer(&admission.id, &target(), &manifest)
        .unwrap();
    let frame = sender
        .serve_chunks(&ChunkRequest {
            attachment_id: manifest.attachment_id.clone(),
            chunk_indices: vec![1],
            execution: None,
        })
        .unwrap()
        .remove(0);
    store
        .save_user_transfer_chunk(&admission.id, &frame)
        .unwrap();
    let saved = store.user_transfer(&admission.id).unwrap().unwrap();
    store
        .save_user_transfer_chunk(&admission.id, &frame)
        .unwrap();
    assert_eq!(
        store
            .user_transfer(&admission.id)
            .unwrap()
            .unwrap()
            .view
            .revision,
        saved.view.revision
    );
    drop(store);
    let store = Persistence::open_with_dek(&path, [44; 32]).unwrap();
    let saved = store.user_transfer(&admission.id).unwrap().unwrap();
    assert_eq!(saved.view.completed_bytes, u64::from(CHUNK_SIZE));
    assert_eq!(saved.view.state, State::WaitingExecution);
    assert_eq!(store.user_transfers().unwrap(), vec![saved.view]);
    let mut receiver = AttachmentRuntime::new();
    receiver.register_incoming(saved.manifest.unwrap()).unwrap();
    for frame in store.user_transfer_chunks(&admission.id).unwrap() {
        receiver.ingest_chunk(&frame).unwrap();
    }
    assert!(receiver
        .next_chunk_request(&manifest.attachment_id)
        .is_none());
    assert_eq!(
        receiver
            .incoming_progress(&manifest.attachment_id)
            .unwrap()
            .completed_chunks,
        1
    );
    drop(store);
    let file = std::fs::read(&path).unwrap();
    for secret in [
        "private-conversation",
        "private-name.bin",
        "original-attachment",
    ] {
        assert!(!file
            .windows(secret.len())
            .any(|window| window == secret.as_bytes()));
    }
}

#[test]
fn binding_and_failed_checkpoint_commit_preserve_the_previous_durable_facts() {
    let directory = TempDirectory::new("transfer-checkpoint-refusal");
    let store = Arc::new(
        Persistence::open_with_dek(&directory.path().join("history.redb"), [45; 32]).unwrap(),
    );
    let (mut sender, manifest) = manifest();
    let admission = store
        .prepare_user_transfer(
            target(),
            Direction::Download,
            Some(manifest.attachment_id.clone()),
            manifest.total_size,
        )
        .unwrap();
    let mut other = target();
    other.id = "unrelated-conversation".into();
    assert!(store
        .bind_user_transfer(&admission.id, &other, &manifest)
        .is_err());
    assert_eq!(
        store
            .user_transfer(&admission.id)
            .unwrap()
            .unwrap()
            .view
            .revision,
        1
    );
    store
        .bind_user_transfer(&admission.id, &target(), &manifest)
        .unwrap();
    let frame = sender
        .serve_chunks(&ChunkRequest {
            attachment_id: manifest.attachment_id.clone(),
            chunk_indices: vec![0],
            execution: None,
        })
        .unwrap()
        .remove(0);
    let fault = store.refuse_background_delivery_writes();
    assert!(store
        .save_user_transfer_chunk(&admission.id, &frame)
        .is_err());
    drop(fault);
    assert!(store
        .user_transfer_chunks(&admission.id)
        .unwrap()
        .is_empty());
    assert_eq!(
        store
            .user_transfer(&admission.id)
            .unwrap()
            .unwrap()
            .view
            .completed_bytes,
        0
    );
    store
        .set_user_transfer_state(&admission.id, State::Cancelled)
        .unwrap();
    assert!(store
        .save_user_transfer_chunk(&admission.id, &frame)
        .is_err());
    assert!(store.user_transfer("../../history").is_err());
}

#[test]
fn deleting_a_conversation_retires_its_execution_and_partial_checkpoint_atomically() {
    let directory = TempDirectory::new("transfer-conversation-delete");
    let store =
        Persistence::open_with_dek(&directory.path().join("history.redb"), [46; 32]).unwrap();
    let (mut sender, manifest) = manifest();
    let admission = store
        .prepare_user_transfer(
            target(),
            Direction::Download,
            Some(manifest.attachment_id.clone()),
            manifest.total_size,
        )
        .unwrap();
    store
        .bind_user_transfer(&admission.id, &target(), &manifest)
        .unwrap();
    let frame = sender
        .serve_chunks(&ChunkRequest {
            attachment_id: manifest.attachment_id,
            chunk_indices: vec![0],
            execution: None,
        })
        .unwrap()
        .remove(0);
    store
        .save_user_transfer_chunk(&admission.id, &frame)
        .unwrap();
    store.delete_session(&target().id).unwrap();
    assert!(store.user_transfers().unwrap().is_empty());
    assert!(store
        .user_transfer_chunks(&admission.id)
        .unwrap()
        .is_empty());
}

#[test]
fn current_os_work_is_bounded_without_losing_historical_send_admissions() {
    let directory = TempDirectory::new("transfer-current-index");
    let store =
        Persistence::open_with_dek(&directory.path().join("history.redb"), [47; 32]).unwrap();
    let mut first = None;
    for _ in 0..130 {
        let admission = store
            .prepare_user_transfer(target(), Direction::Upload, None, 9)
            .unwrap();
        first.get_or_insert(admission.id.clone());
        store
            .set_user_transfer_state(&admission.id, State::WaitingReceiver)
            .unwrap();
    }
    assert_eq!(store.current_user_transfers().unwrap().len(), 64);
    assert_eq!(store.user_transfers().unwrap().len(), 130);
    let id = first.unwrap();
    store
        .set_user_transfer_state(&id, State::WaitingExecution)
        .unwrap();
    assert_eq!(store.current_user_transfers().unwrap().len(), 65);
    assert!(store
        .current_user_transfers()
        .unwrap()
        .iter()
        .any(|view| view.id == id));
    store.remove_user_transfer(&id).unwrap();
    assert!(!store
        .current_user_transfers()
        .unwrap()
        .iter()
        .any(|view| view.id == id));
    store.delete_session(&target().id).unwrap();
    assert!(store.current_user_transfers().unwrap().is_empty());
}

#[test]
fn startup_repairs_a_live_admission_missing_its_new_current_index() {
    let directory = TempDirectory::new("transfer-index-migration");
    let store =
        Persistence::open_with_dek(&directory.path().join("history.redb"), [48; 32]).unwrap();
    let record = store
        .prepare_user_transfer(target(), Direction::Download, Some("original".into()), 9)
        .unwrap();
    store
        .set_user_transfer_state(&record.id, State::WaitingExecution)
        .unwrap();
    store
        .write(|tx| Persistence::remove_current_transfer(tx, &record.id))
        .unwrap();
    assert!(store.current_user_transfers().unwrap().is_empty());
    store.restore_current_transfer_index().unwrap();
    assert_eq!(store.current_user_transfers().unwrap()[0].id, record.id);
}
