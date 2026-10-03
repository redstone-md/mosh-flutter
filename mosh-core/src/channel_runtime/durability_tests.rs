use super::*;
use crate::moss_ffi::{drain_received_messages, fail_next_test_publish, MOSS_TEST_LOCK};

use crate::test_temp_directory::TempDirectory;

struct Fixture {
    store: Arc<Persistence>,
    runtime: ChannelRuntime,
    id: String,
    directory: TempDirectory,
}

impl Fixture {
    fn new() -> Self {
        drain_received_messages();
        let directory = TempDirectory::new("mosh-channel-durable");
        let store = Arc::new(
            Persistence::open_with_dek(&directory.path().join("history.redb"), [57; 32]).unwrap(),
        );
        let attachments = Arc::new(AttachmentStore::new(directory.path()).unwrap());
        let moss = Arc::new(MossFfiRuntime::load_default().unwrap());
        let mut runtime = ChannelRuntime::from_shared(moss, attachments, Some(store.clone()));
        let id = runtime
            .join(JoinChannelRequest {
                name: "durable-channel".into(),
                display_name: "Alice".into(),
                listen_port: 42347,
                static_peer: None,
            })
            .unwrap()
            .name;
        Self {
            store,
            runtime,
            id,
            directory,
        }
    }

    fn restart(&mut self) {
        let attachments = Arc::new(AttachmentStore::new(self.directory.path()).unwrap());
        let moss = Arc::new(MossFfiRuntime::load_default().unwrap());
        self.runtime = ChannelRuntime::from_shared(moss, attachments, Some(self.store.clone()));
        self.runtime.rehydrate();
    }
}

fn assert_attachment(snapshot: &ChannelSnapshot, attachment_id: &str) {
    assert_eq!(
        snapshot.messages[0]
            .attachment
            .as_ref()
            .unwrap()
            .attachment_id,
        attachment_id
    );
}

#[test]
fn refused_attachment_history_keeps_poll_and_list_available_until_repair() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let fault = fixture.store.refuse_message_writes(CHANNEL_HISTORY);
    let sent = fixture
        .runtime
        .send_attachment(
            &fixture.id,
            "durable.txt".into(),
            "text/plain".into(),
            b"published attachment".to_vec(),
            None,
            None,
        )
        .unwrap();

    let snapshot = fixture
        .runtime
        .poll(&fixture.id)
        .expect("reads stay available");
    assert_attachment(&snapshot, &sent.attachment_id);
    let channels = fixture.runtime.list().unwrap().channels;
    assert_attachment(&channels[0], &sent.attachment_id);
    drop(fault);
    fixture.runtime.poll(&fixture.id).unwrap();
    let saved = fixture.store.list_channel_messages(&fixture.id).unwrap();
    assert_eq!(saved.len(), 1);
    fixture.restart();
    let restored = fixture.runtime.poll(&fixture.id).unwrap();
    assert_attachment(&restored, &sent.attachment_id);
}

#[test]
fn refused_storage_does_not_publish_and_retains_a_deliberate_retry() {
    let _lock = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let mut fixture = Fixture::new();
    let fault = fixture.store.refuse_message_writes(CHANNEL_HISTORY);
    let _publication = fail_next_test_publish("publication was deferred");
    let error = fixture
        .runtime
        .send(&fixture.id, "durable first".into())
        .unwrap_err();
    assert!(matches!(error, ChannelRuntimeError::Persistence(_)));
    drop(fault);
    let snapshot = fixture.runtime.poll(&fixture.id).unwrap();
    assert_eq!(
        snapshot.messages[0].delivery_status,
        Some(MessageDeliveryStatus::Failed)
    );
    let message_id = snapshot.messages[0].message_id.clone().unwrap();
    let deferred = fixture
        .runtime
        .retry_message(&fixture.id, &message_id)
        .unwrap();
    assert_eq!(deferred.delivery_status, MessageDeliveryStatus::Failed);
    assert!(deferred
        .delivery_error
        .as_deref()
        .unwrap()
        .contains("publication was deferred"));
    let sent = fixture
        .runtime
        .retry_message(&fixture.id, &message_id)
        .unwrap();
    assert_eq!(sent.delivery_status, MessageDeliveryStatus::Sent);
    assert!(fixture
        .store
        .get_outbound_attempt(CHANNEL_HISTORY.outbound_scope, &fixture.id, &message_id)
        .unwrap()
        .is_none());
    let path = fixture.directory.path().to_path_buf();
    let released = Arc::downgrade(&fixture.store);
    drop(fixture);
    assert!(
        released.upgrade().is_none(),
        "database handles should close"
    );
    assert!(!path.exists(), "fixture directory should be removed");
}
