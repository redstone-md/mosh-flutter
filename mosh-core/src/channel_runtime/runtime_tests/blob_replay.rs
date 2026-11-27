use super::fixture::{Fixture, ROOM};
use super::*;

/// The sender's chunk frames for the whole file, as published on the blob
/// topic. Serving the same chunk again yields the same bytes.
fn served_chunks(sender: &mut Fixture, attachment_id: &str) -> Vec<MossReceivedMessage> {
    let session = sender.runtime.channels.get_mut(ROOM).unwrap();
    let request = crate::attachment_runtime::ChunkRequest {
        attachment_id: attachment_id.into(),
        chunk_indices: vec![0],
        execution: None,
    };
    let frames = session.transfer.serve(&request);
    assert!(!frames.is_empty(), "the sender holds the file");
    frames
        .into_iter()
        .map(|frame| MossReceivedMessage {
            channel: session.blob_topic.clone(),
            payload: serde_json::to_vec(&ChannelBlobEnvelope::Chunk {
                from_fingerprint: session.device_fingerprint.clone(),
                frame,
            })
            .unwrap(),
        })
        .collect()
}

// A member who saw a file's chunks go by while another member downloaded it
// must still take them when the sender serves them again for its own
// download: chunk frames are deterministic, so the second copy is
// byte-identical to the first.
#[test]
fn a_chunk_seen_before_the_download_is_taken_when_served_again() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let (mut sender, mut receiver) = (Fixture::new(), Fixture::new());
    let sent = sender
        .runtime
        .send_attachment(
            ROOM,
            "file.bin".into(),
            "application/octet-stream".into(),
            vec![42; 32],
            None,
            None,
        )
        .unwrap();
    let session = sender.runtime.channels.get(ROOM).unwrap();
    let manifest = session.transfer.manifest_for(&sent.attachment_id).unwrap();
    receiver.deliver(MossReceivedMessage {
        channel: session.blob_topic.clone(),
        payload: serde_json::to_vec(&ChannelBlobEnvelope::Manifest {
            from_device: session.display_name.clone(),
            from_fingerprint: session.device_fingerprint.clone(),
            manifest: Box::new(manifest.into()),
        })
        .unwrap(),
    });
    let chunks = served_chunks(&mut sender, &sent.attachment_id);
    for chunk in chunks.clone() {
        receiver.deliver(chunk);
    }

    receiver
        .runtime
        .download_attachment(ROOM, &sent.attachment_id)
        .unwrap();
    for chunk in chunks {
        receiver.deliver(chunk);
    }

    let snapshot = receiver.runtime.poll(ROOM).unwrap();
    assert_eq!(
        snapshot.attachments[0].state,
        crate::conversation::attachments::AttachmentState::Available
    );
}
