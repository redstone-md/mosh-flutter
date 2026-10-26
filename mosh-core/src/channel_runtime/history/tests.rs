//! Protocol input is delivered at the existing native inbox; assertions use snapshots.
use super::*;
use crate::moss_ffi::{drain_received_messages, MOSS_TEST_LOCK};
use crate::test_temp_directory::TempDirectory;
use ed25519_dalek::SigningKey;

pub(super) const EMPTY_JOURNAL: &str =
    "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945";

pub(super) struct Fixture {
    pub runtime: ChannelRuntime,
    pub store: Arc<Persistence>,
    _directory: TempDirectory,
}

impl Fixture {
    pub fn new() -> Self {
        drain_received_messages();
        let directory = TempDirectory::new("channel-recovery");
        let store = Arc::new(
            Persistence::open_with_dek(&directory.path().join("history"), [81; 32]).unwrap(),
        );
        let _identity = crate::moss_ffi::replace_test_keystore(Some(store.clone()));
        let runtime = ChannelRuntime::from_shared(
            Arc::new(MossFfiRuntime::load_default().unwrap()),
            Arc::new(AttachmentStore::new(directory.path()).unwrap()),
            Some(store.clone()),
        );
        Self {
            runtime,
            store,
            _directory: directory,
        }
    }
    pub fn restart(&mut self) {
        let _identity = crate::moss_ffi::replace_test_keystore(Some(self.store.clone()));
        self.runtime = ChannelRuntime::from_shared(
            Arc::new(MossFfiRuntime::load_default().unwrap()),
            Arc::new(AttachmentStore::new(self._directory.path()).unwrap()),
            Some(self.store.clone()),
        );
        self.runtime.rehydrate();
    }
    pub fn join(&mut self, id: &str) {
        let _identity = crate::moss_ffi::replace_test_keystore(Some(self.store.clone()));
        self.runtime
            .join(JoinChannelRequest {
                name: id.into(),
                display_name: "Reader".into(),
                listen_port: 0,
                static_peer: None,
            })
            .unwrap();
        self.runtime.poll(id).unwrap();
    }
    pub fn deliver(
        &mut self,
        id: &str,
        source: &SigningKey,
        payload: HistoryMessage<ChannelRecord>,
    ) {
        let session = self.runtime.channels.get(id).unwrap();
        let mut frame = HistoryFrame {
            version: 1,
            conversation: session.deletions.context.clone(),
            mesh_id: session.mesh_id.clone(),
            channel: session.blob_topic.clone(),
            sender_key: String::new(),
            recipient_key: Some(session.device_fingerprint.clone()),
            request_id: session.recovery.checkpoint.progress.request_id.clone(),
            round: session.recovery.checkpoint.round,
            payload_b64: String::new(),
            signature: String::new(),
        };
        frame.seal(source, &payload).unwrap();
        inbox::deliver(MossReceivedMessage {
            channel: session.blob_topic.clone(),
            payload: serde_json::to_vec(&ChannelBlobEnvelope::History { frame }).unwrap(),
        });
        self.runtime.poll(id).unwrap();
    }
    pub fn offer(&mut self, id: &str, source: &SigningKey, total: usize) {
        self.deliver(
            id,
            source,
            HistoryMessage::Offer {
                manifest: "a".repeat(64),
                total,
                deletion_digest: EMPTY_JOURNAL.into(),
            },
        );
    }
    pub fn manifest(&self, id: &str) -> String {
        self.runtime
            .channels
            .get(id)
            .unwrap()
            .recovery
            .checkpoint
            .progress
            .manifest
            .clone()
            .unwrap()
    }
    pub fn offer_rows(&mut self, id: &str, source: &SigningKey, rows: &[ChannelRecord]) {
        let keys = rows
            .iter()
            .map(
                |record| crate::conversation::recovery::manifest::HistoryKey {
                    message_id: record.message_id.clone(),
                    sent_at_ms: record.sent_at_ms,
                    digest: crate::conversation::recovery::manifest::digest(record).unwrap(),
                },
            )
            .collect::<Vec<_>>();
        let manifest =
            crate::conversation::recovery::manifest::digest(&(1, format!("channel:{id}"), keys))
                .unwrap();
        self.deliver(
            id,
            source,
            HistoryMessage::Offer {
                manifest,
                total: rows.len(),
                deletion_digest: EMPTY_JOURNAL.into(),
            },
        );
    }
    pub fn journal(&mut self, id: &str, source: &SigningKey) {
        self.deliver(
            id,
            source,
            HistoryMessage::Journal {
                manifest: self.manifest(id),
                deletion_digest: EMPTY_JOURNAL.into(),
                page: crate::message_deletion::protocol::DeletionMessage::State {
                    records: Vec::new(),
                    next: None,
                },
            },
        );
    }
}

#[test]
fn only_four_conversations_import_at_once() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let source = SigningKey::from_bytes(&[28; 32]);
    for index in 0..5 {
        let id = format!("limited-{index}");
        fixture.join(&id);
        fixture.offer(&id, &source, 1);
    }
    let snapshot = fixture.runtime.list().unwrap();
    assert_eq!(
        snapshot
            .channels
            .iter()
            .filter(|c| c
                .history_sync
                .as_ref()
                .is_some_and(|h| h.state == HistorySyncState::Importing))
            .count(),
        4
    );
    assert_eq!(
        snapshot
            .channels
            .iter()
            .filter(|c| c
                .history_sync
                .as_ref()
                .is_some_and(|h| h.state == HistorySyncState::WaitingForSource))
            .count(),
        1
    );
    assert!(snapshot.channels.iter().all(|c| c.messages.is_empty()));
}
