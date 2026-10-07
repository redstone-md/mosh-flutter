use super::*;

pub(super) fn authenticated_legacy_history_can_be_erased_across_own_devices(f: &mut Fixture) {
    let packet = f.packet(
        &f.source,
        DeviceMessage::HistoryBatch(
            f.batch(0, vec![record("old-1", "first"), record("old-2", "second")]),
        ),
    );
    f.receive(&packet).unwrap();
    let snapshot = f.snapshot();
    assert!(snapshot
        .messages
        .iter()
        .all(|m| m
            .metadata
            .as_ref()
            .is_some_and(|metadata| !metadata.local_only
                && metadata.origin.is_none()
                && metadata.deletion_key.is_some())));
    let deleted = f
        .runtime
        .delete_messages(
            &f.session,
            &["old-1".into()],
            crate::message_deletion::DeleteScope::ForMe,
        )
        .unwrap();
    assert_eq!(deleted.local_only_count, 0);
    let store = f.runtime.sessions.persistence().unwrap();
    assert_eq!(
        store
            .account_deletions(&f.receiver.roster().user_id())
            .unwrap()
            .len(),
        1
    );
    f.runtime.rehydrate();
    let snapshot = f.snapshot();
    assert_eq!(snapshot.messages.len(), 1);
    assert_eq!(snapshot.messages[0].body, "second");
}

pub(super) fn legacy_source_preserves_verified_live_origins(f: &mut Fixture) {
    let crypto = &f.peers[&f.contact.device().device_id];
    let origin = crate::message_deletion::MessageOrigin::sign_mls(
        &format!("dm:{}", f.session),
        "overlap",
        b"live",
        crypto,
        None,
        None,
    )
    .unwrap();
    let mut live = record("overlap", "live");
    live.metadata = Some(crate::message_deletion::MessageMetadata {
        origin: Some(origin.clone()),
        ..Default::default()
    });
    f.runtime
        .session_mut(&f.session)
        .unwrap()
        .messages
        .push(live.clone().into_message());
    live.metadata = None;
    let packet = f.packet(
        &f.source,
        DeviceMessage::HistoryBatch(f.batch(0, vec![live, record("other", "second")])),
    );
    f.receive(&packet).unwrap();
    assert_eq!(f.history_sync(), Some(DmHistorySyncState::Complete));
    let snapshot = f.snapshot();
    assert_eq!(snapshot.messages.len(), 2);
    let overlap = snapshot
        .messages
        .iter()
        .find(|m| m.message_id.as_deref() == Some("overlap"))
        .unwrap();
    assert_eq!(overlap.metadata.as_ref().unwrap().origin, Some(origin));
}
