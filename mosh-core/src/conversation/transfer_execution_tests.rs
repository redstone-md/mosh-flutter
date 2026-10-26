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
