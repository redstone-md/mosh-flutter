//! Real chunk movement under cancellation and admission failures.
use super::*;

#[test]
fn refused_download_admission_does_not_claim_running_work() {
    let mut slots = AttachmentSlots::default();
    let mut runtime = AttachmentRuntime::new();
    let manifest = AttachmentRuntime::new()
        .prepare_outgoing(outgoing("missing", vec![1, 2, 3]))
        .unwrap();
    slots.offer(descriptor_of(&manifest));
    assert!(slots.start_download("missing", &mut runtime).is_err());
    assert!(slots.awaiting_chunks().is_empty());
    assert_eq!(slots.views(&runtime)[0].state, AttachmentState::Offered);
}

#[test]
fn explicit_retry_after_cancel_resumes_missing_chunks_and_verifies_the_file() {
    let source = Scratch::open("cancel-resume-source");
    let destination = Scratch::open("cancel-resume-destination");
    let bytes = vec![9; 3 * crate::attachment_runtime::CHUNK_SIZE as usize];
    let mut sender = source.transfer();
    let manifest = send(&mut sender, "resumable", bytes.clone());
    let mut receiver = destination.transfer();
    receiver.accept_manifest(manifest).unwrap();
    receiver.start_download("resumable").unwrap();
    let request = receiver.next_requests().remove(0);
    let first = sender.serve(&request).remove(0);
    receiver.ingest(&first).unwrap();
    receiver.cancel("resumable").unwrap();
    assert!(receiver.next_requests().is_empty());
    receiver.start_download("resumable").unwrap();
    let requests = receiver.next_requests();
    assert!(
        !requests.is_empty(),
        "explicit retry must resume actual byte requests"
    );
    assert!(!requests
        .iter()
        .any(|request| request.chunk_indices.contains(&first.chunk_index)));
    for request in requests {
        for frame in sender.serve(&request) {
            receiver.ingest(&frame).unwrap();
        }
    }
    let view = receiver.views().remove(0);
    assert_eq!(view.state, AttachmentState::Available);
    assert_eq!(std::fs::read(view.local_path.unwrap()).unwrap(), bytes);
}

#[test]
fn unsolicited_original_chunks_remain_an_offer_without_creating_a_cached_file() {
    let source = Scratch::open("unsolicited-source");
    let destination = Scratch::open("unsolicited-destination");
    let mut sender = source.transfer();
    let manifest = send(&mut sender, "unsolicited", vec![42; 400]);
    let mut receiver = destination.transfer();
    receiver.accept_manifest(manifest.clone()).unwrap();
    // A peer may possess the valid crypto but still cannot initiate this user's
    // download. No original or clear-preview request was admitted locally.
    for frame in sender.serve(&ChunkRequest {
        attachment_id: manifest.attachment_id.clone(),
        chunk_indices: vec![0],
        execution: None,
    }) {
        receiver.ingest(&frame).unwrap();
    }
    let view = receiver.views().remove(0);
    assert_eq!(view.state, AttachmentState::Offered);
    assert_eq!(view.completed_chunks, 0);
    assert!(view.local_path.is_none());
    assert!(!destination
        .store
        .exists(&manifest.content_hash, &manifest.file_name)
        .unwrap());
}

#[test]
fn refused_final_file_commit_is_failed_and_explicit_retry_can_finish() {
    let source = Scratch::open("final-write-source");
    let destination = Scratch::open("final-write-destination");
    let mut sender = source.transfer();
    let bytes = vec![54; 400];
    let manifest = send(&mut sender, "final-write", bytes.clone());
    let path = destination
        .store
        .path_for(&manifest.content_hash, &manifest.file_name)
        .unwrap();
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    let blocked = path.with_file_name(format!("{}.partial", manifest.file_name));
    std::fs::create_dir(&blocked).unwrap();
    let mut receiver = destination.transfer();
    receiver.accept_manifest(manifest).unwrap();
    receiver.start_download("final-write").unwrap();
    let request = receiver.next_requests().remove(0);
    assert!(receiver.ingest(&sender.serve(&request).remove(0)).is_err());
    assert_eq!(receiver.views()[0].state, AttachmentState::Failed);
    std::fs::remove_dir(blocked).unwrap();
    receiver.start_download("final-write").unwrap();
    for request in receiver.next_requests() {
        for frame in sender.serve(&request) {
            receiver.ingest(&frame).unwrap();
        }
    }
    assert_eq!(receiver.views()[0].state, AttachmentState::Available);
    assert_eq!(
        std::fs::read(receiver.views()[0].local_path.as_ref().unwrap()).unwrap(),
        bytes
    );
}
