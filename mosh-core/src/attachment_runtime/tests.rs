use super::*;

fn payload(size: usize) -> Vec<u8> {
    (0..size).map(|index| (index % 251) as u8).collect()
}

fn drive_transfer(bytes: Vec<u8>) -> Vec<u8> {
    let mut sender = AttachmentRuntime::new();
    let mut receiver = AttachmentRuntime::new();
    let manifest = sender
        .prepare_outgoing(outgoing("att-1", bytes.clone()))
        .unwrap();
    receiver.register_incoming(manifest).unwrap();
    receiver.start_download("att-1").unwrap();

    for _ in 0..10_000 {
        let Some(request) = receiver.next_chunk_request("att-1") else {
            break;
        };
        let frames = sender.serve_chunks(&request).unwrap();
        assert!(!frames.is_empty());
        for frame in frames {
            match receiver.ingest_chunk(&frame).unwrap() {
                ChunkOutcome::Complete { bytes, .. } => return bytes,
                ChunkOutcome::Progress(_) => {}
                other => panic!("unexpected outcome {other:?}"),
            }
        }
    }
    panic!("transfer never completed");
}

/// A full chunk frame, base64'd once more by the stream carrier and
/// wrapped by moss, must still fit one macOS UDP datagram (9216 bytes by
/// default). 32 KB chunks did not, and Mac-to-Mac voice notes crawled.
#[test]
fn a_full_chunk_frame_fits_a_macos_datagram() {
    const MACOS_MAX_DATAGRAM: usize = 9216;
    const MOSS_OVERHEAD_BUDGET: usize = 1024;
    let mut sender = AttachmentRuntime::new();
    let manifest = sender
        .prepare_outgoing(outgoing("att-size", payload(CHUNK_SIZE as usize)))
        .unwrap();
    let frames = sender
        .serve_chunks(&ChunkRequest {
            attachment_id: manifest.attachment_id,
            chunk_indices: vec![0],
        })
        .unwrap();

    let json = serde_json::to_vec(&frames[0]).unwrap().len();
    let on_the_wire = json.div_ceil(3) * 4 + MOSS_OVERHEAD_BUDGET;
    assert!(on_the_wire <= MACOS_MAX_DATAGRAM, "{on_the_wire} bytes");
}

/// An older sender serves at most 64 chunks per request. Asking it for
/// more would leave the rest waiting out the 10 s request timeout.
#[test]
fn a_32k_manifest_is_requested_in_batches_an_old_sender_serves() {
    assert_eq!(request_batch(32 * 1024), 64);
    assert_eq!(request_batch(CHUNK_SIZE), MAX_REQUEST_BATCH);
}

#[test]
fn single_chunk_round_trip() {
    let bytes = payload(1024);
    assert_eq!(drive_transfer(bytes.clone()), bytes);
}

#[test]
fn multi_chunk_round_trip() {
    let bytes = payload((CHUNK_SIZE as usize) * 3 + 17);
    assert_eq!(drive_transfer(bytes.clone()), bytes);
}

#[test]
fn rejects_oversized_attachment() {
    let mut runtime = AttachmentRuntime::new();
    let huge = vec![0u8; (MAX_ATTACHMENT_SIZE + 1) as usize];
    assert!(matches!(
        runtime.prepare_outgoing(outgoing("x", huge)),
        Err(AttachmentRuntimeError::TooLarge { .. })
    ));
}

#[test]
fn rejects_empty_attachment() {
    let mut runtime = AttachmentRuntime::new();
    assert!(matches!(
        runtime.prepare_outgoing(outgoing("x", Vec::new())),
        Err(AttachmentRuntimeError::Empty)
    ));
}

#[test]
fn drops_thumbnail_that_would_blow_the_gossipsub_cap() {
    let mut runtime = AttachmentRuntime::new();
    let manifest = runtime
        .prepare_outgoing(OutgoingAttachment {
            thumbnail_b64: Some("A".repeat(MAX_THUMBNAIL_B64 + 1)),
            ..outgoing("a", payload(1024))
        })
        .unwrap();
    assert!(manifest.thumbnail_b64.is_none());
    // Manifest must stay well under Moss's 64KB gossipsub payload cap.
    let json = serde_json::to_vec(&manifest).unwrap();
    assert!(json.len() < 64 * 1024, "manifest is {} bytes", json.len());
}

#[test]
fn keeps_thumbnail_within_budget() {
    let mut runtime = AttachmentRuntime::new();
    let manifest = runtime
        .prepare_outgoing(OutgoingAttachment {
            thumbnail_b64: Some("A".repeat(MAX_THUMBNAIL_B64)),
            ..outgoing("a", payload(1024))
        })
        .unwrap();
    assert_eq!(
        manifest.thumbnail_b64.as_deref().map(str::len),
        Some(MAX_THUMBNAIL_B64)
    );
}

#[test]
fn duplicate_chunk_is_idempotent() {
    let mut sender = AttachmentRuntime::new();
    let mut receiver = AttachmentRuntime::new();
    let manifest = sender
        .prepare_outgoing(outgoing("a", payload(2048)))
        .unwrap();
    receiver.register_incoming(manifest).unwrap();
    let request = ChunkRequest {
        attachment_id: "a".to_string(),
        chunk_indices: vec![0],
    };
    let frames = sender.serve_chunks(&request).unwrap();
    let frame = frames.into_iter().next().unwrap();
    receiver.ingest_chunk(&frame).unwrap();
    assert!(matches!(
        receiver.ingest_chunk(&frame).unwrap(),
        ChunkOutcome::Duplicate
    ));
}

#[test]
fn corrupted_chunk_is_rejected() {
    let mut sender = AttachmentRuntime::new();
    let mut receiver = AttachmentRuntime::new();
    let manifest = sender
        .prepare_outgoing(outgoing("a", payload(512)))
        .unwrap();
    receiver.register_incoming(manifest).unwrap();
    let request = ChunkRequest {
        attachment_id: "a".to_string(),
        chunk_indices: vec![0],
    };
    let mut frame = sender.serve_chunks(&request).unwrap().remove(0);
    frame.ciphertext_b64 = encode(b"tampered ciphertext bytes here padding");
    assert!(receiver.ingest_chunk(&frame).is_err());
}

#[test]
fn cancel_stops_serving_chunks() {
    let mut sender = AttachmentRuntime::new();
    sender
        .prepare_outgoing(outgoing("a", payload(4096)))
        .unwrap();
    sender.cancel("a");
    let frames = sender
        .serve_chunks(&ChunkRequest {
            attachment_id: "a".to_string(),
            chunk_indices: vec![0],
        })
        .unwrap();
    assert!(frames.is_empty());
}

fn outgoing(id: &str, bytes: Vec<u8>) -> OutgoingAttachment {
    OutgoingAttachment {
        attachment_id: id.into(),
        file_name: "file.bin".into(),
        mime: "application/octet-stream".into(),
        from_fingerprint: "AABB".into(),
        bytes,
        thumbnail_b64: None,
        voice: None,
    }
}

mod download;
