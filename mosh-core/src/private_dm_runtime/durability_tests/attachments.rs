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
