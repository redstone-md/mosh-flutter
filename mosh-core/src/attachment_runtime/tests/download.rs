use super::*;

#[test]
fn next_chunk_request_is_idle_until_download_starts() {
    let mut sender = AttachmentRuntime::new();
    let mut receiver = AttachmentRuntime::new();
    let manifest = sender
        .prepare_outgoing(outgoing("a", payload(4096)))
        .unwrap();
    receiver.register_incoming(manifest).unwrap();
    assert!(receiver.next_chunk_request("a").is_none());
    receiver.start_download("a").unwrap();
    assert!(receiver.next_chunk_request("a").is_some());
}

#[test]
fn next_chunk_request_resumes_gaps_before_advancing() {
    let mut sender = AttachmentRuntime::new();
    let mut receiver = AttachmentRuntime::new();
    let manifest = sender
        .prepare_outgoing(outgoing("a", payload((CHUNK_SIZE as usize) * 3)))
        .unwrap();
    receiver.register_incoming(manifest).unwrap();
    receiver.start_download("a").unwrap();

    let first = receiver.next_chunk_request("a").unwrap();
    assert_eq!(first.chunk_indices, vec![0, 1, 2]);
    // Deliver only chunk 1, leaving 0 and 2 as gaps.
    let frames = sender
        .serve_chunks(&ChunkRequest {
            attachment_id: "a".to_string(),
            chunk_indices: vec![1],
        })
        .unwrap();
    receiver.ingest_chunk(&frames[0]).unwrap();
    // 0 and 2 were asked for a moment ago and count as in flight, so the
    // gap is re-requested only once the window has passed.
    assert!(receiver.next_chunk_request("a").is_none());
    let later = Instant::now() + CHUNK_REQUEST_TIMEOUT;
    let resume = receiver.next_chunk_request_at("a", later).unwrap();
    assert_eq!(resume.chunk_indices, vec![0, 2]);
}

// One lost chunk used to hang a transfer forever: the receiver asked again,
// the request was byte-identical, and the sender's payload-hash dedup
// dropped it. The dedup exemption lives in the DM runtime; this covers the
// half that must not turn the retry into a flood — and that the retry
// happens at all.
#[test]
fn a_lost_chunk_is_asked_for_again_once_the_window_passes() {
    let mut sender = AttachmentRuntime::new();
    let mut receiver = AttachmentRuntime::new();
    let manifest = sender
        .prepare_outgoing(outgoing("a", payload((CHUNK_SIZE as usize) * 2)))
        .unwrap();
    receiver.register_incoming(manifest).unwrap();
    receiver.start_download("a").unwrap();

    let first = receiver.next_chunk_request("a").unwrap();
    assert_eq!(first.chunk_indices, vec![0, 1]);
    // Chunk 1 is lost in transit; chunk 0 arrives.
    let frames = sender.serve_chunks(&first).unwrap();
    receiver.ingest_chunk(&frames[0]).unwrap();

    // Pumping every second must not re-ask while the chunk may still be
    // on the wire.
    let now = Instant::now();
    for tick in 1..5 {
        assert!(
            receiver
                .next_chunk_request_at("a", now + Duration::from_secs(tick))
                .is_none(),
            "re-asked at {tick}s — an in-flight batch would be requested \
             once per pump"
        );
    }

    let retry = receiver
        .next_chunk_request_at("a", now + CHUNK_REQUEST_TIMEOUT)
        .expect("a chunk that never arrived must be asked for again");
    assert_eq!(retry.chunk_indices, vec![1]);
    for frame in sender.serve_chunks(&retry).unwrap() {
        receiver.ingest_chunk(&frame).unwrap();
    }
    assert_eq!(
        sender.served_count("a", 1),
        2,
        "the sender must re-serve the chunk the receiver never got"
    );
}

#[test]
fn a_new_batch_waits_for_room_in_the_inflight_window() {
    let mut sender = AttachmentRuntime::new();
    let manifest = sender
        .prepare_outgoing(outgoing(
            "window",
            payload(CHUNK_SIZE as usize * (MAX_REQUEST_BATCH + 1)),
        ))
        .expect("prepare");
    let mut receiver = AttachmentRuntime::new();
    receiver.register_incoming(manifest).expect("offer");
    receiver.start_download("window").expect("start");
    let now = Instant::now();
    let first = receiver
        .next_chunk_request_at("window", now)
        .expect("first batch");
    assert_eq!(first.chunk_indices.len(), MAX_REQUEST_BATCH);
    assert!(
        receiver
            .next_chunk_request_at("window", now + Duration::from_millis(1))
            .is_none(),
        "one receiver must not queue more chunks than the peer's 256-frame buffer"
    );
    let first_frame = sender.serve_chunks(&first).unwrap().remove(0);
    receiver.ingest_chunk(&first_frame).unwrap();
    let next = receiver
        .next_chunk_request_at("window", now + Duration::from_millis(2))
        .expect("a received chunk frees one request slot");
    assert_eq!(next.chunk_indices, vec![MAX_REQUEST_BATCH as u64]);
}

#[test]
fn stream_range_returns_pending_then_ready() {
    let mut sender = AttachmentRuntime::new();
    let mut receiver = AttachmentRuntime::new();
    let bytes = payload((CHUNK_SIZE as usize) * 3 + 40);
    let manifest = sender
        .prepare_outgoing(OutgoingAttachment {
            mime: "video/mp4".into(),
            ..outgoing("a", bytes.clone())
        })
        .unwrap();
    receiver.register_incoming(manifest).unwrap();

    // Nothing downloaded yet: a range read is pending and arms a priority.
    let start = (CHUNK_SIZE as u64) * 2;
    let end = start + 100;
    assert!(matches!(
        receiver.stream_range("a", start, end),
        StreamRange::Pending { .. }
    ));
    let request = receiver.next_chunk_request("a").unwrap();
    assert_eq!(request.chunk_indices.first().copied(), Some(2));

    // Deliver every chunk, then the same range reads back exactly.
    while let Some(request) = receiver.next_chunk_request("a") {
        for frame in sender.serve_chunks(&request).unwrap() {
            let _ = receiver.ingest_chunk(&frame).unwrap();
        }
    }
    match receiver.stream_range("a", start, end) {
        StreamRange::Ready {
            bytes: slice,
            total_size,
            mime,
        } => {
            assert_eq!(total_size, bytes.len() as u64);
            assert_eq!(mime, "video/mp4");
            assert_eq!(slice, &bytes[start as usize..end as usize]);
        }
        other => panic!("expected Ready, got {other:?}"),
    }
}

#[test]
fn register_incoming_rejects_bad_chunk_count() {
    let mut runtime = AttachmentRuntime::new();
    let manifest = AttachmentManifest {
        origin: None,
        attachment_id: "a".to_string(),
        content_hash: "0".repeat(64),
        file_name: "f".to_string(),
        mime: "m".to_string(),
        total_size: 1024,
        chunk_size: CHUNK_SIZE,
        chunk_count: 99,
        key_b64: encode(&[0u8; ATTACHMENT_KEY_LEN]),
        nonce_prefix_b64: encode(&[0u8; ATTACHMENT_NONCE_PREFIX_LEN]),
        thumbnail_b64: None,
        voice: None,
        from_fingerprint: "fp".to_string(),
    };
    assert!(matches!(
        runtime.register_incoming(manifest),
        Err(AttachmentRuntimeError::ManifestMismatch(_))
    ));
}

#[test]
fn prepare_outgoing_stamps_voice_onto_the_manifest() {
    let mut runtime = AttachmentRuntime::new();
    let voice = VoiceMeta {
        duration_ms: 1000,
        peaks_b64: "AAA=".to_string(),
    };
    let manifest = runtime
        .prepare_outgoing(OutgoingAttachment {
            voice: Some(voice),
            ..outgoing("att-1", vec![1, 2, 3, 4])
        })
        .expect("prepare");
    let stamped = manifest.voice.expect("voice present");
    assert_eq!(stamped.duration_ms, 1000);
}

#[test]
fn voice_meta_roundtrips_through_json() {
    let meta = VoiceMeta {
        duration_ms: 4200,
        peaks_b64: "AAECAwQF".to_string(),
    };
    let json = serde_json::to_string(&meta).expect("serialize");
    let back: VoiceMeta = serde_json::from_str(&json).expect("deserialize");
    assert_eq!(back.duration_ms, 4200);
    assert_eq!(back.peaks_b64, "AAECAwQF");
}

#[test]
fn manifest_without_voice_omits_the_field() {
    let manifest = AttachmentManifest {
        origin: None,
        attachment_id: "a".into(),
        content_hash: "h".into(),
        file_name: "f".into(),
        mime: "audio/webm".into(),
        total_size: 1,
        chunk_size: 1,
        chunk_count: 1,
        key_b64: "k".into(),
        nonce_prefix_b64: "n".into(),
        thumbnail_b64: None,
        voice: None,
        from_fingerprint: "fp".into(),
    };
    let json = serde_json::to_string(&manifest).expect("serialize");
    assert!(!json.contains("voice"), "voice must be omitted when None");
}
