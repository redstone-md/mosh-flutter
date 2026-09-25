//! One file moved from a sender to a receiver, over the same calls the three
//! runtimes make. Nothing is stubbed: the chunks are really sealed, really
//! verified, and the finished file really lands in a store on disk.

use std::sync::Arc;

use super::*;
use crate::attachment_runtime::VoiceMeta;
use crate::conversation::attachments::AttachmentState;

const FILE: &str = "clip.bin";

/// An attachment root of this test's own, removed when the test ends.
struct Scratch {
    dir: std::path::PathBuf,
    store: Arc<AttachmentStore>,
}

impl Scratch {
    fn open(name: &str) -> Self {
        let dir = std::env::temp_dir().join(format!("mosh-transfer-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("scratch dir");
        let store = Arc::new(AttachmentStore::new(&dir).expect("attachment store"));
        Self { dir, store }
    }

    fn transfer(&self) -> Transfer {
        Transfer::new(Arc::clone(&self.store))
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

fn outgoing(attachment_id: &str, bytes: Vec<u8>) -> OutgoingAttachment {
    OutgoingAttachment {
        attachment_id: attachment_id.to_string(),
        file_name: FILE.to_string(),
        mime: "application/octet-stream".to_string(),
        from_fingerprint: "sender".to_string(),
        bytes,
        thumbnail_b64: None,
        voice: None,
    }
}

/// Sealing a file and putting its manifest on the wire, as a kind does it:
/// prepare, publish (nothing to publish here), then open the slot.
fn send(transfer: &mut Transfer, attachment_id: &str, bytes: Vec<u8>) -> AttachmentManifest {
    let prepared = transfer
        .prepare_outgoing(outgoing(attachment_id, bytes))
        .expect("prepare");
    let manifest = prepared.manifest.clone();
    transfer.record_sent(prepared);
    manifest
}

fn state_of(transfer: &Transfer, attachment_id: &str) -> AttachmentState {
    transfer
        .views()
        .into_iter()
        .find(|view| view.attachment_id == attachment_id)
        .expect("a view for this attachment")
        .state
}

#[test]
fn a_sent_file_is_saved_and_shown_as_available() {
    let scratch = Scratch::open("sent");
    let mut sender = scratch.transfer();

    let prepared = sender
        .prepare_outgoing(outgoing("a1", vec![1, 2, 3, 4]))
        .expect("prepare");
    let manifest = prepared.manifest.clone();
    let descriptor = sender.record_sent(prepared);

    assert_eq!(descriptor.attachment_id, "a1");
    assert_eq!(descriptor.content_hash, manifest.content_hash);
    assert_eq!(descriptor.total_size, 4);
    assert!(sender.holds("a1"));
    assert_eq!(state_of(&sender, "a1"), AttachmentState::Available);
    assert!(scratch
        .store
        .exists(&manifest.content_hash, FILE)
        .expect("store readable"));
}

#[test]
fn a_manifest_carries_the_voice_note_it_was_sent_with() {
    let scratch = Scratch::open("voice");
    let mut sender = scratch.transfer();
    let mut request = outgoing("voice-1", vec![9; 64]);
    request.voice = Some(VoiceMeta {
        duration_ms: 1500,
        peaks_b64: "AQID".to_string(),
    });

    let prepared = sender.prepare_outgoing(request).expect("prepare");
    let manifest = prepared.manifest.clone();
    let descriptor = sender.record_sent(prepared);

    let mut receiver = scratch.transfer();
    let taken = receiver
        .accept_manifest(manifest)
        .expect("accept")
        .expect("a new attachment");
    assert_eq!(
        taken.voice.expect("voice meta").duration_ms,
        descriptor.voice.expect("voice meta").duration_ms
    );
}

#[test]
fn the_same_offer_twice_is_one_attachment() {
    let scratch = Scratch::open("repeat-offer");
    let mut sender = scratch.transfer();
    let manifest = send(&mut sender, "a1", vec![5; 32]);
    let mut receiver = scratch.transfer();

    let first = receiver.accept_manifest(manifest.clone()).expect("accept");
    let second = receiver.accept_manifest(manifest).expect("accept again");

    assert!(first.is_some());
    assert!(
        second.is_none(),
        "a repeat offer must not open a second slot"
    );
    assert_eq!(receiver.views().len(), 1);
}

#[test]
fn a_file_travels_from_the_sender_to_the_receiver() {
    let scratch = Scratch::open("round-trip");
    let bytes: Vec<u8> = (0..2048u32).map(|value| value as u8).collect();
    let mut sender = scratch.transfer();
    let manifest = send(&mut sender, "a1", bytes.clone());

    let mut receiver = scratch.transfer();
    receiver.accept_manifest(manifest.clone()).expect("accept");
    assert_eq!(state_of(&receiver, "a1"), AttachmentState::Offered);
    assert!(
        receiver.next_requests().is_empty(),
        "an offer nobody asked for pulls nothing"
    );

    receiver.start_download("a1").expect("start");
    let requests = receiver.next_requests();
    assert_eq!(requests.len(), 1);

    for request in &requests {
        for frame in sender.serve(request) {
            receiver.ingest(&frame).expect("ingest");
        }
    }

    assert_eq!(state_of(&receiver, "a1"), AttachmentState::Available);
    assert!(
        receiver.next_requests().is_empty(),
        "a finished download stops asking"
    );
    let saved = scratch
        .store
        .read_blob(&manifest.content_hash, FILE)
        .expect("the finished file");
    assert_eq!(saved, bytes);
}

#[test]
fn only_the_sender_can_answer_a_request() {
    let scratch = Scratch::open("serve");
    let mut sender = scratch.transfer();
    let manifest = send(&mut sender, "a1", vec![3; 64]);
    let mut bystander = scratch.transfer();
    bystander.accept_manifest(manifest).expect("accept");
    bystander.start_download("a1").expect("start");
    let request = bystander.next_requests().pop().expect("a request");

    assert!(!sender.serve(&request).is_empty());
    assert!(
        bystander.serve(&request).is_empty(),
        "a member who is not the sender has nothing to serve"
    );
}

#[test]
fn a_chunk_that_does_not_verify_fails_the_slot() {
    let scratch = Scratch::open("bad-chunk");
    let mut sender = scratch.transfer();
    let manifest = send(&mut sender, "a1", vec![8; 64]);
    let mut receiver = scratch.transfer();
    receiver.accept_manifest(manifest).expect("accept");
    receiver.start_download("a1").expect("start");
    let request = receiver.next_requests().pop().expect("a request");
    let mut frame = sender.serve(&request).pop().expect("a chunk");
    frame.ciphertext_b64 = "not the bytes that were sealed".to_string();

    receiver
        .ingest(&frame)
        .expect("a bad chunk is not an error");

    assert_eq!(state_of(&receiver, "a1"), AttachmentState::Failed);
}

#[test]
fn a_restored_attachment_needs_its_bytes_on_disk() {
    let scratch = Scratch::open("restore");
    let mut sender = scratch.transfer();
    let prepared = sender
        .prepare_outgoing(outgoing("a1", vec![4; 16]))
        .expect("prepare");
    let descriptor = sender.record_sent(prepared);
    let mut missing = descriptor.clone();
    missing.content_hash = "0".repeat(64);
    missing.file_name = "never-saved.bin".to_string();

    // A fresh conversation, as a restart leaves it: the slots are gone, the
    // store is not.
    let mut restarted = scratch.transfer();
    restarted.restore_cached(&descriptor, AttachmentDirection::Outgoing);
    restarted.restore_cached(&missing, AttachmentDirection::Incoming);

    assert!(restarted.holds("a1"));
    assert_eq!(state_of(&restarted, "a1"), AttachmentState::Available);
    assert_eq!(restarted.views().len(), 1);
}

#[test]
fn a_cancelled_download_stops_asking_for_chunks() {
    let scratch = Scratch::open("cancel");
    let mut sender = scratch.transfer();
    let manifest = send(&mut sender, "a1", vec![6; 64]);
    let mut receiver = scratch.transfer();
    receiver.accept_manifest(manifest).expect("accept");
    receiver.start_download("a1").expect("start");

    receiver.cancel("a1").expect("cancel");

    assert!(receiver.next_requests().is_empty());
    assert_eq!(state_of(&receiver, "a1"), AttachmentState::Cancelled);
}

#[test]
fn concurrent_downloads_share_the_peer_queue() {
    let sender_store = Scratch::open("parallel-sender");
    let receiver_store = Scratch::open("parallel-receiver");
    let mut sender = sender_store.transfer();
    let mut receiver = receiver_store.transfer();
    for id in ["file", "voice"] {
        let manifest = send(&mut sender, id, vec![5; 256 * 4096]);
        receiver.accept_manifest(manifest).expect("offer");
        receiver.start_download(id).expect("start");
    }
    let requests = receiver.next_requests();
    assert_eq!(requests.len(), 2, "both downloads must make progress");
    assert!(
        requests
            .iter()
            .map(|request| request.chunk_indices.len())
            .sum::<usize>()
            <= 256,
        "both downloads share one peer stream with a 256-frame buffer"
    );
}

#[test]
fn voice_gets_the_next_free_slot_while_a_file_is_downloading() {
    let sender_store = Scratch::open("voice-priority-sender");
    let receiver_store = Scratch::open("voice-priority-receiver");
    let mut sender = sender_store.transfer();
    let mut receiver = receiver_store.transfer();
    let file = send(&mut sender, "file", vec![5; 257 * 4096]);
    receiver.accept_manifest(file).expect("file offer");
    receiver.start_download("file").expect("start file");
    let file_request = receiver.next_requests().remove(0);
    assert_eq!(file_request.chunk_indices.len(), 256);

    let mut voice = outgoing("voice", vec![7; 4096]);
    voice.voice = Some(VoiceMeta {
        duration_ms: 1000,
        peaks_b64: String::new(),
    });
    let prepared = sender.prepare_outgoing(voice).expect("prepare voice");
    let voice_manifest = prepared.manifest.clone();
    sender.record_sent(prepared);
    receiver
        .accept_manifest(voice_manifest)
        .expect("voice offer");
    receiver.start_download("voice").expect("start voice");

    let file_frame = sender.serve(&file_request).remove(0);
    receiver.ingest(&file_frame).expect("one file chunk");
    let requests = receiver.next_requests();
    assert_eq!(requests.len(), 1);
    assert_eq!(requests[0].attachment_id, "voice");
    for frame in sender.serve(&requests[0]) {
        receiver.ingest(&frame).expect("voice chunk");
    }
    assert_eq!(state_of(&receiver, "voice"), AttachmentState::Available);
    assert_eq!(state_of(&receiver, "file"), AttachmentState::Downloading);
}

#[test]
fn a_file_whose_manifest_never_went_out_opens_no_slot() {
    let scratch = Scratch::open("unpublished");
    let mut sender = scratch.transfer();

    // The kind publishes between these two calls. This one never got that
    // far, so there must be nothing for the UI to show: an attachment with no
    // message beside it is a row the user cannot act on.
    let prepared = sender
        .prepare_outgoing(outgoing("a1", vec![2; 32]))
        .expect("prepare");

    assert!(!sender.holds("a1"));
    assert!(sender.views().is_empty());

    // The bytes are already saved, so the send can still be finished.
    sender.record_sent(prepared);
    assert_eq!(state_of(&sender, "a1"), AttachmentState::Available);
}

#[test]
fn asking_for_an_attachment_nobody_offered_says_so() {
    let scratch = Scratch::open("unknown");
    let mut transfer = scratch.transfer();

    assert!(matches!(
        transfer.start_download("stranger"),
        Err(TransferError::Slot(SlotError::Missing(id))) if id == "stranger"
    ));
}
