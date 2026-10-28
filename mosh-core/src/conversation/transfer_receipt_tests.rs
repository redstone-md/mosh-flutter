//! Genuine files, encrypted journals and signatures cross the shared owner.
use super::*;
use crate::api::conversation::{BridgeConversationKind, BridgeConversationRef};
use crate::attachment_runtime::execution::RequestPhase;
use crate::mls_crypto::MlsSessionCrypto;
use crate::persistence::user_transfers::types::{
    UserTransferDirection as Direction, UserTransferState as State,
};
use crate::persistence::{Persistence, DM_HISTORY};

fn target() -> BridgeConversationRef {
    BridgeConversationRef {
        kind: BridgeConversationKind::Dm,
        id: "receipt-session".into(),
    }
}
fn journal(scratch: &Scratch, byte: u8) -> Arc<Persistence> {
    Arc::new(Persistence::open_with_dek(&scratch.dir.join("execution.redb"), [byte; 32]).unwrap())
}
fn signed(request: &mut ChunkRequest, key: &MlsSessionCrypto) {
    let author = hex::encode(key.signer_public());
    request
        .sign_execution(&author, |token, bytes| {
            crate::message_deletion::MessageOrigin::sign_mls(
                "transfer:dm:receipt-session",
                token,
                bytes,
                key,
                None,
                None,
            )
        })
        .unwrap();
}

#[test]
fn only_the_exact_receiver_can_complete_an_upload_even_after_sender_restart() {
    let source = Scratch::open("receipt-source");
    let destination = Scratch::open("receipt-destination");
    let source_journal = journal(&source, 73);
    let destination_journal = journal(&destination, 74);
    let mut source_key = MlsSessionCrypto::new("source").unwrap();
    source_key.create_group().unwrap();
    let mut receiver_key = MlsSessionCrypto::new("receiver").unwrap();
    let mut attacker = MlsSessionCrypto::new("other-member").unwrap();
    let receiver_package = receiver_key.key_package_bytes().unwrap();
    let attacker_package = attacker.key_package_bytes().unwrap();
    let joined = source_key
        .add_members(&[&receiver_package, &attacker_package])
        .unwrap();
    receiver_key
        .join_welcome(&joined.welcome_bytes, &joined.tree_bytes)
        .unwrap();
    attacker
        .join_welcome(&joined.welcome_bytes, &joined.tree_bytes)
        .unwrap();
    assert_eq!(
        source_key
            .member_identity_for_signer(&attacker.signer_public())
            .as_deref(),
        Some("other-member")
    );
    let bytes = vec![87; crate::attachment_runtime::CHUNK_SIZE as usize * 3];
    let mut sender = source.transfer();
    sender.attach_execution(source_journal.clone(), DM_HISTORY, &target().id);
    let admission = source_journal
        .prepare_user_transfer(target(), Direction::Upload, None, bytes.len() as u64)
        .unwrap();
    let mut outgoing = sender
        .prepare_outgoing(outgoing("receipted", bytes.clone()))
        .unwrap();
    outgoing.manifest.origin = Some(
        crate::message_deletion::MessageOrigin::sign_mls(
            "dm:receipt-session",
            "receipted",
            b"manifest",
            &source_key,
            None,
            None,
        )
        .unwrap(),
    );
    let manifest = outgoing.manifest.clone();
    let sealed_manifest = source_key
        .encrypt(&serde_json::to_vec(&manifest).unwrap())
        .unwrap();
    let shared_manifest: crate::attachment_runtime::AttachmentManifest =
        serde_json::from_slice(&attacker.decrypt(&sealed_manifest).unwrap()).unwrap();
    assert_eq!(shared_manifest.key_b64, manifest.key_b64);
    receiver_key.decrypt(&sealed_manifest).unwrap();
    sender
        .bind_user_admission(Some(&admission.id), &manifest)
        .unwrap();
    sender.record_sent(outgoing);
    let mut receiver = destination.transfer();
    receiver.accept_manifest(manifest.clone()).unwrap();
    receiver.attach_execution(destination_journal.clone(), DM_HISTORY, &target().id);
    let download = destination_journal
        .prepare_user_transfer(
            target(),
            Direction::Download,
            Some("receipted".into()),
            bytes.len() as u64,
        )
        .unwrap();
    receiver
        .bind_download_admission("receipted", &download.id)
        .unwrap();
    receiver.start_download("receipted").unwrap();
    let mut request = receiver.next_requests().remove(0);
    signed(&mut request, &receiver_key);
    let frames = sender.serve(&request);
    assert_eq!(frames.len(), 3);
    sender.chunks_published(&frames);
    assert_ne!(
        source_journal
            .user_transfer(&admission.id)
            .unwrap()
            .unwrap()
            .view
            .state,
        State::Complete
    );
    for frame in &frames {
        receiver.ingest(frame).unwrap();
    }
    assert_eq!(
        std::fs::read(receiver.views()[0].local_path.as_ref().unwrap()).unwrap(),
        bytes
    );
    let mut completion = receiver
        .next_requests()
        .into_iter()
        .find(|request| request.execution.as_ref().unwrap().phase == RequestPhase::Complete)
        .unwrap();
    signed(&mut completion, &receiver_key);
    drop(sender);
    let mut sender = source.transfer();
    sender.restore_stored(
        &descriptor_of(&manifest),
        AttachmentDirection::Outgoing,
        Some(manifest),
    );
    sender.attach_execution(source_journal.clone(), DM_HISTORY, &target().id);
    let mut forged = completion.clone();
    signed(&mut forged, &attacker);
    assert!(sender.serve(&forged).is_empty());
    assert_ne!(
        source_journal
            .user_transfer(&admission.id)
            .unwrap()
            .unwrap()
            .view
            .state,
        State::Complete
    );
    assert!(sender.serve(&completion).is_empty());
    let saved = source_journal
        .user_transfer(&admission.id)
        .unwrap()
        .unwrap()
        .view;
    assert_eq!(saved.state, State::Complete);
    assert_eq!(saved.completed_bytes, saved.total_bytes);
    let mut ack = sender
        .next_requests()
        .into_iter()
        .find(|request| request.execution.as_ref().unwrap().phase == RequestPhase::Ack)
        .unwrap();
    signed(&mut ack, &source_key);
    assert!(receiver.serve(&ack).is_empty());
    // Replaying the genuine receipt is idempotent, and changes in its indices,
    // context or claimed receiver invalidate the original signature.
    let revision = saved.revision;
    sender.serve(&completion);
    assert_eq!(
        source_journal
            .user_transfer(&admission.id)
            .unwrap()
            .unwrap()
            .view
            .revision,
        revision
    );
    completion.execution.as_mut().unwrap().receiver = hex::encode(attacker.signer_public());
    assert!(completion
        .verify_execution("transfer:dm:receipt-session")
        .is_err());
}

#[test]
fn native_partial_checkpoint_restarts_with_only_missing_bytes_requested() {
    let source = Scratch::open("checkpoint-native-source");
    let destination = Scratch::open("checkpoint-native-destination");
    let journal = journal(&destination, 75);
    let mut sender = source.transfer();
    let bytes = vec![92; crate::attachment_runtime::CHUNK_SIZE as usize * 3];
    let manifest = send(&mut sender, "checkpoint-native", bytes.clone());
    let mut receiver = destination.transfer();
    receiver.accept_manifest(manifest.clone()).unwrap();
    receiver.attach_execution(journal.clone(), DM_HISTORY, &target().id);
    let admission = journal
        .prepare_user_transfer(
            target(),
            Direction::Download,
            Some(manifest.attachment_id.clone()),
            bytes.len() as u64,
        )
        .unwrap();
    receiver
        .bind_download_admission(&manifest.attachment_id, &admission.id)
        .unwrap();
    receiver.start_download(&manifest.attachment_id).unwrap();
    let request = ChunkRequest {
        attachment_id: manifest.attachment_id.clone(),
        chunk_indices: vec![1],
        execution: None,
    };
    receiver.ingest(&sender.serve(&request).remove(0)).unwrap();
    receiver.cancel(&manifest.attachment_id).unwrap();
    let resumed = journal
        .prepare_user_transfer(
            target(),
            Direction::Download,
            Some(manifest.attachment_id.clone()),
            bytes.len() as u64,
        )
        .unwrap();
    assert_eq!(resumed.id, admission.id);
    assert_eq!(
        resumed.completed_bytes,
        u64::from(crate::attachment_runtime::CHUNK_SIZE)
    );
    drop(receiver);
    let mut receiver = destination.transfer();
    receiver.restore_stored(
        &descriptor_of(&manifest),
        AttachmentDirection::Incoming,
        Some(manifest.clone()),
    );
    receiver.attach_execution(journal.clone(), DM_HISTORY, &target().id);
    for request in receiver.next_requests() {
        assert!(!request.chunk_indices.contains(&1));
        // This source fixture is a legacy foreground sender.
        let mut legacy = request;
        legacy.execution = None;
        for frame in sender.serve(&legacy) {
            receiver.ingest(&frame).unwrap();
        }
    }
    receiver.refresh_execution().unwrap();
    assert_eq!(
        std::fs::read(receiver.views()[0].local_path.as_ref().unwrap()).unwrap(),
        bytes
    );
    assert_eq!(
        journal
            .user_transfer(&admission.id)
            .unwrap()
            .unwrap()
            .view
            .state,
        State::Complete
    );
}

#[test]
fn forgetting_a_transfer_cannot_flush_buffered_chunks_back_into_deleted_storage() {
    let source = Scratch::open("buffered-delete-source");
    let destination = Scratch::open("buffered-delete-destination");
    let journal = journal(&destination, 76);
    let mut sender = source.transfer();
    let manifest = send(&mut sender, "buffered-delete", vec![9; 8192]);
    let mut receiver = destination.transfer();
    receiver.accept_manifest(manifest.clone()).unwrap();
    receiver.attach_execution(journal.clone(), DM_HISTORY, &target().id);
    let admitted = journal
        .prepare_user_transfer(
            target(),
            Direction::Download,
            Some(manifest.attachment_id.clone()),
            manifest.total_size,
        )
        .unwrap();
    receiver
        .bind_download_admission(&manifest.attachment_id, &admitted.id)
        .unwrap();
    receiver.start_download(&manifest.attachment_id).unwrap();
    let request = ChunkRequest {
        attachment_id: manifest.attachment_id.clone(),
        chunk_indices: vec![0],
        execution: None,
    };
    let frame = sender.serve(&request).remove(0);
    receiver.ingest(&frame).unwrap();
    receiver.forget(&manifest.attachment_id);
    receiver.refresh_execution().unwrap();
    receiver.ingest(&frame).unwrap();
    assert!(journal.user_transfers().unwrap().is_empty());
    assert!(journal.current_user_transfers().unwrap().is_empty());
    assert!(journal
        .user_transfer_chunks(&admitted.id)
        .unwrap()
        .is_empty());
    assert!(!receiver.holds(&manifest.attachment_id));
}
