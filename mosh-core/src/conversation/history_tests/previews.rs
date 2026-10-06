use super::*;
use crate::conversation::attachments::AttachmentState;

const PREVIEW: &[u8] = include_bytes!("../../../tests/fixtures/preview.jpg");

fn message(descriptor: super::super::super::attachments::AttachmentDescriptor) -> ChatMessage {
    ChatMessage {
        metadata: None,
        from_device: "alice".into(),
        body: String::new(),
        message_id: Some("photo".into()),
        sent_at_ms: Some(100),
        attachment: Some(descriptor),
        call_event: None,
        delivery_status: None,
        delivery_error: None,
        retryable: None,
        retry_count: None,
        read: None,
    }
}

fn replay(scratch: &Scratch, transfer: &mut Transfer, local_author: &str) {
    let mut log = MessageLog::<ChatMessage>::default();
    History::new(DM_HISTORY).replay(
        &scratch.persistence,
        CONVERSATION,
        Restore {
            log: &mut log,
            attempts: &mut Attempts::new(),
            transfer,
            local_author,
        },
    );
    assert_eq!(log.len(), 1);
    assert_eq!(transfer.views().len(), 1);
}

#[test]
fn a_pending_preview_resumes_from_encrypted_history_after_both_peers_restart() {
    let sender = Scratch::open("preview-pending-sender");
    let receiver = Scratch::open("preview-pending-receiver");
    let mut sending = sender.transfer();
    let mut prepared = sending
        .prepare_offer(
            OutgoingAttachment {
                attachment_id: "photo".into(),
                file_name: "photo.png".into(),
                mime: "image/png".into(),
                from_fingerprint: "alice".into(),
                bytes: vec![42; 100_000],
                thumbnail_b64: Some(crate::conversation::encode(include_bytes!(
                    "../../../tests/fixtures/miniature.jpg"
                ))),
                voice: None,
            },
            Some(PREVIEW.to_vec()),
        )
        .unwrap();
    prepared
        .sign(
            &format!("dm:{CONVERSATION}"),
            &ed25519_dalek::SigningKey::from_bytes(&[3; 32]),
            None,
        )
        .unwrap();
    let offer = prepared.offer();
    let descriptor = sending.record_sent(prepared);
    let mut receiving = receiver.transfer();
    receiving.accept_offer(offer).unwrap();
    let mut log = MessageLog::default();
    log.push(message(descriptor));
    for (scratch, transfer) in [(&sender, &sending), (&receiver, &receiving)] {
        History::new(DM_HISTORY)
            .write_tail(&scratch.persistence, CONVERSATION, &log, Some(transfer))
            .unwrap();
    }
    drop((sending, receiving));
    let mut sending = sender.transfer();
    let mut receiving = receiver.transfer();
    replay(&sender, &mut sending, "alice");
    replay(&receiver, &mut receiving, "bob");
    for request in receiving.next_requests() {
        assert_eq!(request.attachment_id, "photo/preview");
        for chunk in sending.serve(&request) {
            receiving.ingest(&chunk).unwrap();
        }
    }
    let view = receiving.views().remove(0);
    assert_eq!(view.state, AttachmentState::Offered);
    assert!(view.local_path.is_none());
    assert_eq!(std::fs::read(view.preview_path.unwrap()).unwrap(), PREVIEW);
}
