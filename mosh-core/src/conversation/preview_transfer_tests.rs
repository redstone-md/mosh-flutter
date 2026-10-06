use super::*;

pub(super) const PREVIEW: &[u8] = include_bytes!("../../tests/fixtures/preview.jpg");

pub(super) fn image(id: &str) -> OutgoingAttachment {
    OutgoingAttachment {
        attachment_id: id.into(),
        file_name: "screenshot.png".into(),
        mime: "image/png".into(),
        from_fingerprint: "sender".into(),
        bytes: vec![42; 100_000],
        thumbnail_b64: Some(crate::conversation::encode(include_bytes!(
            "../../tests/fixtures/miniature.jpg"
        ))),
        voice: None,
    }
}

#[test]
fn a_failed_preview_cache_write_can_retry_without_an_orphaned_transfer() {
    let scratch = Scratch::open("preview-failed-cache");
    let mut transfer = scratch.transfer();
    let path = scratch
        .store
        .path_for(
            &crate::attachment_crypto::sha256_hex(PREVIEW),
            "preview.jpg",
        )
        .unwrap();
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    let partial = path.with_file_name("preview.jpg.partial");
    std::fs::create_dir(&partial).unwrap();
    assert!(transfer
        .prepare_offer(image("photo"), Some(PREVIEW.to_vec()))
        .is_err());
    assert!(
        transfer.manifest_for("photo/preview").is_none(),
        "failed preview must release its plaintext and key"
    );
    std::fs::remove_dir(partial).unwrap();
    assert!(transfer
        .prepare_offer(image("photo"), Some(PREVIEW.to_vec()))
        .is_ok());
}

#[test]
fn the_clear_preview_downloads_automatically_without_downloading_the_original() {
    let sent = Scratch::open("preview-sender");
    let received = Scratch::open("preview-receiver");
    let mut sender = sent.transfer();
    let mut receiver = received.transfer();
    let outgoing = sender
        .prepare_offer(image("photo"), Some(PREVIEW.to_vec()))
        .unwrap();
    let offer = outgoing.offer();
    sender.record_sent(outgoing);
    receiver.accept_offer(offer).unwrap();
    assert!(receiver.preview_path("photo").is_none());
    let requests = receiver.next_requests();
    assert!(!requests.is_empty());
    for request in requests {
        assert_ne!(request.attachment_id, "photo");
        for frame in sender.serve(&request) {
            receiver.ingest(&frame).unwrap();
        }
    }
    let views = receiver.views();
    assert_eq!(views.len(), 1, "the preview is not another attachment row");
    assert_eq!(views[0].attachment_id, "photo");
    assert_eq!(views[0].state, AttachmentState::Offered);
    assert!(views[0].local_path.is_none());
    let path = receiver
        .preview_path("photo")
        .expect("the clear preview is ready");
    assert_eq!(std::fs::read(path).unwrap(), PREVIEW);
    assert!(receiver.next_requests().is_empty());
}

#[test]
fn corrupt_preview_chunks_retry_while_the_original_stays_offered() {
    let sent = Scratch::open("preview-retry-sender");
    let received = Scratch::open("preview-retry-receiver");
    let mut sender = sent.transfer();
    let mut receiver = received.transfer();
    let outgoing = sender
        .prepare_offer(image("photo"), Some(PREVIEW.to_vec()))
        .unwrap();
    receiver.accept_offer(outgoing.offer()).unwrap();
    sender.record_sent(outgoing);
    let request = receiver.next_requests().remove(0);
    let mut chunk = sender.serve(&request).remove(0);
    chunk.ciphertext_b64 = "invalid ciphertext".into();
    receiver.ingest(&chunk).unwrap();
    assert!(receiver.next_requests().is_empty(), "retry must back off");
    let requests = receiver.next_requests_at(Instant::now() + std::time::Duration::from_secs(6));
    assert!(!requests.is_empty());
    for request in requests {
        for chunk in sender.serve(&request) {
            receiver.ingest(&chunk).unwrap();
        }
    }
    assert!(receiver.preview_path("photo").is_some());
    assert_eq!(state_of(&receiver, "photo"), AttachmentState::Offered);
}

#[test]
fn automatic_previews_are_bounded_and_precede_original_downloads() {
    let sent = Scratch::open("preview-priority-sender");
    let received = Scratch::open("preview-priority-receiver");
    let mut sender = sent.transfer();
    let mut receiver = received.transfer();
    for index in 0..6 {
        let id = format!("photo-{index}");
        let outgoing = sender
            .prepare_offer(image(&id), Some(PREVIEW.to_vec()))
            .unwrap();
        receiver.accept_offer(outgoing.offer()).unwrap();
        sender.record_sent(outgoing);
    }
    receiver.start_download("photo-0").unwrap();
    let mut voice = outgoing("voice", vec![7; 4096]);
    voice.voice = Some(VoiceMeta {
        duration_ms: 1000,
        peaks_b64: String::new(),
    });
    let voice = sender.prepare_outgoing(voice).unwrap();
    receiver.accept_manifest(voice.manifest.clone()).unwrap();
    sender.record_sent(voice);
    receiver.start_download("voice").unwrap();
    let requests = receiver.next_requests();
    assert_eq!(requests[0].attachment_id, "voice");
    assert_eq!(
        requests
            .iter()
            .filter(|r| r.attachment_id.ends_with("/preview"))
            .count(),
        4
    );
    assert_eq!(requests.last().unwrap().attachment_id, "photo-0");
    for request in requests
        .iter()
        .filter(|r| r.attachment_id.ends_with("/preview"))
    {
        for frame in sender.serve(request) {
            receiver.ingest(&frame).unwrap();
        }
    }
    assert_eq!(
        receiver
            .next_requests()
            .iter()
            .filter(|r| r.attachment_id.ends_with("/preview"))
            .count(),
        2
    );
}

#[test]
fn deleting_the_parent_discards_preview_requests_and_late_chunks() {
    let sent = Scratch::open("preview-deleted-sender");
    let received = Scratch::open("preview-deleted-receiver");
    let mut sender = sent.transfer();
    let mut receiver = received.transfer();
    let outgoing = sender
        .prepare_offer(image("photo"), Some(PREVIEW.to_vec()))
        .unwrap();
    receiver.accept_offer(outgoing.offer()).unwrap();
    sender.record_sent(outgoing);
    let request = receiver.next_requests().remove(0);
    let chunks = sender.serve(&request);
    receiver.forget("photo");
    for chunk in chunks {
        receiver.ingest(&chunk).unwrap();
    }
    assert!(receiver.views().is_empty());
    assert!(receiver.next_requests().is_empty());
    assert!(receiver.preview_path("photo").is_none());
}

#[test]
fn shared_preview_cache_survives_until_the_last_parent_is_deleted() {
    let scratch = Scratch::open("preview-shared-cache");
    let mut transfer = scratch.transfer();
    let first = transfer
        .prepare_offer(image("first"), Some(PREVIEW.to_vec()))
        .unwrap();
    let preview = descriptor_of(first.offer().preview_manifest.as_ref().unwrap());
    transfer.record_sent(first);
    let second = transfer
        .prepare_offer(image("second"), Some(PREVIEW.to_vec()))
        .unwrap();
    transfer.record_sent(second);
    transfer.forget("first");
    assert!(!transfer.clean_erased(&preview, None).unwrap());
    assert!(transfer.preview_path("second").is_some());
    transfer.forget("second");
    assert!(transfer.clean_erased(&preview, None).unwrap());
}

#[test]
fn a_cold_history_preview_reference_preserves_the_cached_blob() {
    let scratch = Scratch::open("preview-cold-history");
    let mut transfer = scratch.transfer();
    let outgoing = transfer
        .prepare_offer(image("photo"), Some(PREVIEW.to_vec()))
        .unwrap();
    let manifest = outgoing.offer().preview_manifest.unwrap();
    let descriptor = descriptor_of(&manifest);
    transfer.record_sent(outgoing);
    let store =
        crate::persistence::Persistence::open_with_dek(&scratch.dir.join("history"), [7; 32])
            .unwrap();
    let row = serde_json::json!({"message": {}, "preview_manifest": manifest});
    store
        .append_message("other", 1, "reference", &serde_json::to_vec(&row).unwrap())
        .unwrap();
    transfer.forget("photo");
    assert!(!transfer.clean_erased(&descriptor, Some(&store)).unwrap());
    store.delete_session("other").unwrap();
    assert!(transfer.clean_erased(&descriptor, Some(&store)).unwrap());
}
