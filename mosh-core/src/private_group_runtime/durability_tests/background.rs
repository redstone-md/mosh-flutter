use super::*;

#[test]
fn native_incoming_group_receipt_queues_one_durable_notification_before_any_ui_poll() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let (mut sender, identity) = super::history::member(&mut fixture);
    fixture.store.save_background_intent(false, true).unwrap();
    let frame = super::history::text(
        &fixture,
        &mut sender,
        &identity,
        "background-incoming",
        "native receipt",
    );
    let repeated = MossReceivedMessage {
        channel: frame.channel.clone(),
        payload: frame.payload.clone(),
    };
    let fault = fixture.store.refuse_group_snapshot_writes();
    inbox::deliver(frame);
    fixture.runtime.service().unwrap();
    assert!(fixture
        .store
        .pending_background_notifications(16)
        .unwrap()
        .is_empty());
    drop(fault);
    inbox::deliver(repeated);
    fixture.runtime.service().unwrap();
    let pending = fixture.store.pending_background_notifications(16).unwrap();
    assert_eq!(pending.len(), 1);
    assert_eq!(pending[0].message_count, 1);
    assert_eq!(pending[0].text.as_deref(), Some("native receipt"));
    fixture.restart();
    assert_eq!(
        fixture
            .store
            .pending_background_notifications(16)
            .unwrap()
            .len(),
        1
    );
    fixture
        .store
        .ack_background_notification(&pending[0].id, pending[0].revision)
        .unwrap();
    fixture.runtime.service().unwrap();
    assert!(fixture
        .store
        .pending_background_notifications(16)
        .unwrap()
        .is_empty());
}

#[test]
fn background_counts_only_started_downloads_and_refuses_unsaved_work() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    assert_eq!(fixture.runtime.background_work().unwrap(), (0, 0));
    offer_attachment(&mut fixture);
    assert_eq!(fixture.runtime.background_work().unwrap(), (0, 0));
    fixture
        .runtime
        .download_attachment(&fixture.id, "user-download")
        .unwrap();
    assert_eq!(fixture.runtime.background_work().unwrap(), (0, 1));
    fixture
        .runtime
        .cancel_attachment(&fixture.id, "user-download")
        .unwrap();
    assert_eq!(fixture.runtime.background_work().unwrap(), (0, 0));

    let refused = fixture.store.refuse_message_writes(GROUP_HISTORY);
    assert!(fixture
        .runtime
        .send(&fixture.id, "needs durability".into())
        .is_err());
    assert!(fixture.runtime.background_work().is_err());
    drop(refused);
    assert_eq!(fixture.runtime.background_work().unwrap(), (0, 0));
    assert_eq!(
        fixture
            .store
            .list_group_messages(&fixture.id)
            .unwrap()
            .len(),
        1
    );
}

fn offer_attachment(fixture: &mut Fixture) {
    let mut sender = Transfer::new(Arc::new(
        AttachmentStore::new(fixture.directory.path().join("sender")).unwrap(),
    ));
    let prepared = sender
        .prepare_outgoing(OutgoingAttachment {
            attachment_id: "user-download".into(),
            file_name: "file.txt".into(),
            mime: "text/plain".into(),
            bytes: b"requested bytes".to_vec(),
            from_fingerprint: "sender".into(),
            thumbnail_b64: None,
            voice: None,
        })
        .unwrap();
    fixture
        .runtime
        .groups
        .get_mut(&fixture.id)
        .unwrap()
        .transfer
        .accept_manifest(prepared.manifest)
        .unwrap();
}
