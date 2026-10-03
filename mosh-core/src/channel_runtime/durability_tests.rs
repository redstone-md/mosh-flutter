use super::*;
use crate::moss_ffi::{drain_received_messages, fail_next_test_publish, MOSS_TEST_LOCK};

struct Fixture {
    directory: std::path::PathBuf,
    store: Arc<Persistence>,
    runtime: ChannelRuntime,
    id: String,
}

impl Fixture {
    fn new() -> Self {
        drain_received_messages();
        let directory =
            std::env::temp_dir().join(format!("mosh-channel-durable-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&directory);
        std::fs::create_dir_all(&directory).unwrap();
        let store = Arc::new(
            Persistence::open_with_dek(&directory.join("history.redb"), [57; 32]).unwrap(),
        );
        let attachments = Arc::new(AttachmentStore::new(&directory).unwrap());
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
            directory,
            store,
            runtime,
            id,
        }
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.directory);
    }
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
}
