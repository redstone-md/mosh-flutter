use super::*;

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
        AttachmentStore::new(&fixture.directory.path().join("sender")).unwrap(),
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
