use super::*;
use crate::attachment_runtime::OutgoingAttachment;

fn descriptor(id: &str) -> AttachmentDescriptor {
    AttachmentDescriptor {
        attachment_id: id.to_string(),
        content_hash: format!("hash-{id}"),
        file_name: format!("{id}.bin"),
        mime: "application/octet-stream".to_string(),
        total_size: 1,
        thumbnail_b64: None,
        voice: None,
    }
}

/// Registers a real incoming transfer, so `start_download` talks to the
/// same transfer state the runtime uses in production.
fn offered(slots: &mut AttachmentSlots, attachments: &mut AttachmentRuntime, id: &str) {
    let manifest = AttachmentRuntime::new()
        .prepare_outgoing(OutgoingAttachment {
            attachment_id: id.to_string(),
            file_name: format!("{id}.bin"),
            mime: "application/octet-stream".to_string(),
            from_fingerprint: "peer".to_string(),
            bytes: vec![7, 7, 7],
            thumbnail_b64: None,
            voice: None,
        })
        .expect("manifest");
    attachments
        .register_incoming(manifest.clone())
        .expect("register");
    slots.offer(descriptor_of(&manifest));
}

#[test]
fn only_requested_incoming_transfers_await_chunks() {
    let mut attachments = AttachmentRuntime::new();
    let mut slots = AttachmentSlots::default();
    offered(&mut slots, &mut attachments, "wanted");
    offered(&mut slots, &mut attachments, "untouched");
    offered(&mut slots, &mut attachments, "cancelled");
    slots.record_sent(descriptor("mine"), "C:/tmp/mine.bin".to_string());

    slots
        .start_download("wanted", &mut attachments)
        .expect("start");
    slots
        .start_download("cancelled", &mut attachments)
        .expect("start");
    slots.cancel("cancelled", &mut attachments).expect("cancel");

    assert_eq!(slots.awaiting_chunks(), vec!["wanted".to_string()]);
}

#[test]
fn a_finished_download_stops_asking_for_chunks() {
    let mut attachments = AttachmentRuntime::new();
    let mut slots = AttachmentSlots::default();
    offered(&mut slots, &mut attachments, "photo");
    slots
        .start_download("photo", &mut attachments)
        .expect("start");
    assert_eq!(slots.awaiting_chunks(), vec!["photo".to_string()]);

    slots.fail("photo");
    slots.complete_download("photo", "C:/tmp/photo.bin".to_string());

    assert!(slots.awaiting_chunks().is_empty());
    let view = &slots.views(&attachments)[0];
    assert_eq!(view.state, AttachmentState::Available);
    assert_eq!(view.local_path.as_deref(), Some("C:/tmp/photo.bin"));
}

#[test]
fn own_attachments_cannot_be_downloaded() {
    let mut attachments = AttachmentRuntime::new();
    let mut slots = AttachmentSlots::default();
    slots.record_sent(descriptor("mine"), "C:/tmp/mine.bin".to_string());

    assert!(matches!(
        slots.start_download("mine", &mut attachments),
        Err(SlotError::NotIncoming)
    ));
    assert!(matches!(
        slots.start_download("stranger", &mut attachments),
        Err(SlotError::Missing(id)) if id == "stranger"
    ));
}

#[test]
fn views_report_each_state_and_keep_a_stable_order() {
    let mut attachments = AttachmentRuntime::new();
    let mut slots = AttachmentSlots::default();
    offered(&mut slots, &mut attachments, "b-downloading");
    offered(&mut slots, &mut attachments, "c-offered");
    offered(&mut slots, &mut attachments, "d-failed");
    offered(&mut slots, &mut attachments, "e-cancelled");
    slots.record_sent(descriptor("a-sent"), "C:/tmp/a.bin".to_string());
    slots
        .start_download("b-downloading", &mut attachments)
        .expect("start");
    slots.fail("d-failed");
    slots
        .cancel("e-cancelled", &mut attachments)
        .expect("cancel");

    let states: Vec<(String, AttachmentState)> = slots
        .views(&attachments)
        .into_iter()
        .map(|view| (view.attachment_id, view.state))
        .collect();
    assert_eq!(
        states,
        vec![
            ("a-sent".to_string(), AttachmentState::Available),
            ("b-downloading".to_string(), AttachmentState::Downloading),
            ("c-offered".to_string(), AttachmentState::Offered),
            ("d-failed".to_string(), AttachmentState::Failed),
            ("e-cancelled".to_string(), AttachmentState::Cancelled),
        ]
    );
}

#[test]
fn an_unknown_chunk_falls_back_to_a_plain_file_name() {
    let mut slots = AttachmentSlots::default();
    slots.offer(descriptor("known"));

    assert_eq!(slots.file_name("known"), "known.bin");
    assert_eq!(slots.file_name("stranger"), UNNAMED_FILE);
}

#[test]
fn a_replayed_attachment_keeps_the_first_record() {
    let mut attachments = AttachmentRuntime::new();
    let mut slots = AttachmentSlots::default();

    // History is replayed oldest first, and one file can be stamped on more
    // than one message — the same bytes sent and later received back share an
    // attachment id, because the id comes from the content.
    slots.restore(
        descriptor("shared"),
        AttachmentDirection::Outgoing,
        "C:/tmp/first.bin".to_string(),
    );
    slots.restore(
        descriptor("shared"),
        AttachmentDirection::Incoming,
        "C:/tmp/second.bin".to_string(),
    );

    let view = &slots.views(&attachments)[0];
    assert_eq!(view.direction, OUTGOING_LABEL);
    assert_eq!(view.local_path.as_deref(), Some("C:/tmp/first.bin"));
    // A restored file is on disk, so it never asks for chunks either way.
    assert!(slots.awaiting_chunks().is_empty());
    assert!(matches!(
        slots.start_download("shared", &mut attachments),
        Err(SlotError::NotIncoming)
    ));
}

#[test]
fn playback_pulls_an_attachment_the_user_never_asked_for() {
    let mut attachments = AttachmentRuntime::new();
    let mut slots = AttachmentSlots::default();
    offered(&mut slots, &mut attachments, "voice");
    assert!(slots.awaiting_chunks().is_empty());

    slots.resume_for_stream("voice", &mut attachments);

    assert_eq!(slots.awaiting_chunks(), vec!["voice".to_string()]);
    assert_eq!(
        slots.views(&attachments)[0].state,
        AttachmentState::Downloading
    );
}

#[test]
fn streaming_an_unknown_attachment_is_ignored() {
    let mut attachments = AttachmentRuntime::new();
    let mut slots = AttachmentSlots::default();

    slots.resume_for_stream("stranger", &mut attachments);

    assert!(slots.awaiting_chunks().is_empty());
    assert!(slots.views(&attachments).is_empty());
}

#[test]
fn a_cancelled_download_starts_again_when_playback_asks() {
    let mut attachments = AttachmentRuntime::new();
    let mut slots = AttachmentSlots::default();
    offered(&mut slots, &mut attachments, "clip");
    slots
        .start_download("clip", &mut attachments)
        .expect("start");
    slots.cancel("clip", &mut attachments).expect("cancel");

    slots.resume_for_stream("clip", &mut attachments);

    assert_eq!(slots.awaiting_chunks(), vec!["clip".to_string()]);
}
