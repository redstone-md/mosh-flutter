use super::*;
use crate::persistence::test_faults::TableFault;
use std::sync::Mutex;

type HeldFault = Arc<Mutex<Option<TableFault>>>;

fn refuse_manifest_tail(pair: &Pair) -> HeldFault {
    let fault = Arc::new(Mutex::new(None));
    let held = fault.clone();
    let store = pair.store.clone();
    pair.net.drop_frames(ALICE_ID, BOB_ID, move |_, payload| {
        if matches!(
            serde_json::from_slice::<ControlEnvelope>(payload),
            Ok(ControlEnvelope::AttachmentManifest { .. })
        ) {
            held.lock()
                .unwrap()
                .get_or_insert_with(|| store.refuse_message_writes(DM_HISTORY));
        }
        false
    });
    fault
}

fn assert_attachment_survives_tail_refusal(case: &str, voice: Option<VoiceMeta>) {
    let mut pair = Pair::new(case);
    let fault = refuse_manifest_tail(&pair);
    let duration = voice.as_ref().map(|voice| voice.duration_ms);
    let result = pair.alice.send_attachment(
        &pair.session_id,
        "published.bin".into(),
        "application/octet-stream".into(),
        vec![7; 1024],
        None,
        voice,
    );
    let received = pair.bob.poll_session(&pair.session_id).unwrap();
    assert_eq!(received.messages.len(), 1, "the manifest reached the peer");
    assert!(
        fault.lock().unwrap().is_some(),
        "real storage refused the tail"
    );
    let sent = result.expect("published attachment must keep its successful result");
    assert_eq!(
        received.messages[0]
            .attachment
            .as_ref()
            .unwrap()
            .attachment_id,
        sent.attachment_id
    );
    pair.alice.service();
    pair.net.drop_frames(ALICE_ID, BOB_ID, |_, _| false);
    drop(fault.lock().unwrap().take());
    pair.alice.service();
    pair.restart_alice();
    let restored = pair.alice.poll_session(&pair.session_id).unwrap();
    assert_eq!(
        restored.messages.len(),
        1,
        "tail retry keeps one history row"
    );
    let attachment = restored.messages[0].attachment.as_ref().unwrap();
    assert_eq!(attachment.attachment_id, sent.attachment_id);
    assert_eq!(attachment.content_hash, sent.content_hash);
    assert_eq!(
        attachment.voice.as_ref().map(|voice| voice.duration_ms),
        duration
    );
    assert_eq!(restored.attachments[0].state, AttachmentState::Available);
}

#[test]
fn published_file_survives_a_refused_tail_save() {
    assert_attachment_survives_tail_refusal("file-tail", None);
}

#[test]
fn published_voice_message_survives_a_refused_tail_save() {
    assert_attachment_survives_tail_refusal(
        "voice-tail",
        Some(VoiceMeta {
            duration_ms: 1200,
            peaks_b64: encode(&[7; 64]),
        }),
    );
}

#[test]
fn incoming_attachment_creates_one_durable_background_notice_without_downloading() {
    let mut pair = Pair::new("background-offer");
    let store = pair.bob.sessions.persistence().cloned().unwrap();
    store.save_background_intent(false, true).unwrap();
    let sent = pair
        .alice
        .send_attachment(
            &pair.session_id,
            "offered.bin".into(),
            "application/octet-stream".into(),
            vec![7; 1024],
            None,
            None,
        )
        .unwrap();
    pair.bob.service();
    let pending = store.pending_background_notifications(16).unwrap();
    assert_eq!(pending.len(), 1, "an authenticated offer must notify");
    assert_eq!(pending[0].target.id, pair.session_id);
    let snapshot = pair.bob.poll_session(&pair.session_id).unwrap();
    assert_eq!(snapshot.attachments[0].attachment_id, sent.attachment_id);
    assert_eq!(snapshot.attachments[0].state, AttachmentState::Offered);
    assert_eq!(snapshot.attachments[0].completed_chunks, 0);
    assert!(snapshot.attachments[0].local_path.is_none());
    assert_eq!(
        snapshot.messages[0].metadata.as_ref().unwrap().is_own,
        Some(false)
    );
    pair.bob.rehydrate();
    pair.bob.service();
    let restored = store.pending_background_notifications(16).unwrap();
    assert_eq!(restored.len(), 1);
    assert_eq!(restored[0].revision, pending[0].revision);
}
