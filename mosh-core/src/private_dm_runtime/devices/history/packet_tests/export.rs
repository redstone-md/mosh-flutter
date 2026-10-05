//! A recovery checkpoint must not change metadata between exported fragments.
use super::*;

fn source_text(f: &mut Fixture) {
    let session = f.runtime.session_mut(&f.session).unwrap();
    let mut message = record("fragmented-origin", "abcdef").into_message();
    message.metadata = Some(crate::message_deletion::MessageMetadata {
        origin: Some(
            crate::message_deletion::MessageOrigin::sign_mls(
                &format!("dm:{}", f.session),
                "fragmented-origin",
                b"abcdef",
                &session.crypto,
                session.deletions.store.as_ref(),
                session.transport.local_peer_id().as_deref(),
            )
            .unwrap(),
        ),
        ..Default::default()
    });
    session.messages.push_stamped(message);
    f.runtime.sessions.persist_tail().unwrap();
}

pub(super) fn frozen_metadata_survives_a_recovery_checkpoint(f: &mut Fixture) {
    source_text(f);
    let store = f.runtime.sessions.persistence().cloned().unwrap();
    let mut importer = HistoryImport::new("export", f.receiver.device());
    let mut request = HistoryRequest {
        session_id: f.session.clone(),
        request_id: importer.request_id.clone(),
        offset: 0,
        body_offset: 0,
    };
    let packet = f.packet(&f.source, DeviceMessage::HistoryRequest(request.clone()));
    // The real source saves its export before attempting delivery to this offline peer.
    let _ = f.receive(&packet);
    let session = f.runtime.session_mut(&f.session).unwrap();
    let export = session.membership.as_ref().unwrap().history_exports[0].clone();
    let mut first = export.batch(&store, &request).unwrap();
    first.fragment_first(0).unwrap();
    first.fragment.as_mut().unwrap().record.body.truncate(3);
    assert!(importer.accept(&first).unwrap().is_empty());

    // Receiving a matching recovery offer checkpoints all current history.
    session
        .commit_current_history(&store, session.membership.clone().unwrap())
        .unwrap();
    request.body_offset = 3;
    let last = export.batch(&store, &request).unwrap();
    let records = importer
        .accept(&last)
        .expect("the frozen export must survive a recovery checkpoint between fragments");
    assert!(importer.complete);
    assert_eq!(records.len(), 1);
    assert_eq!(records[0].body, "abcdef");
    records[0]
        .validate_content(&format!("dm:{}", f.session))
        .unwrap();
}
