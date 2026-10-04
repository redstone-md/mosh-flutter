use super::*;
use crate::chat_names::{ChatNameErrorKind, NameRecord, NameVersion};
use crate::device_link::names_wire::{self, NameMessage};
use crate::moss_ffi::{MossFfiRuntime, MOSS_TEST_LOCK};
use crate::test_temp_directory::TempDirectory;
use ed25519_dalek::SigningKey;

#[path = "names_sync_tests.rs"]
mod sync;

struct Fixture {
    runtime: DeviceLinkRuntime,
    peer: DeviceIdentity,
    shared: Arc<SharedMossNode>,
    store: Arc<Persistence>,
    _directory: TempDirectory,
}

impl Fixture {
    fn new() -> Self {
        let directory = TempDirectory::new("mosh-names-runtime");
        let store = Arc::new(
            Persistence::open_with_dek(&directory.path().join("local"), [41; 32]).unwrap(),
        );
        let shared = SharedMossNode::new(Arc::new(MossFfiRuntime::load_default().unwrap()));
        let mut runtime = DeviceLinkRuntime::open(shared.clone(), store.clone()).unwrap();
        let remote_store =
            Arc::new(Persistence::open_with_dek(&directory.path().join("peer"), [42; 32]).unwrap());
        let peer_id = hex::encode(SigningKey::from_bytes(&[42; 32]).verifying_key().as_bytes());
        let mut peer = DeviceIdentity::open(remote_store, &peer_id).unwrap();
        let roster = runtime
            .identity
            .roster()
            .extend(peer.device().clone(), &runtime.identity.key())
            .unwrap();
        runtime.identity.adopt_roster(roster.clone()).unwrap();
        let mut record = peer.record.clone();
        record.roster = roster;
        peer.update(record).unwrap();
        Self {
            runtime,
            peer,
            shared,
            store,
            _directory: directory,
        }
    }

    fn receive(&mut self, message: NameMessage) -> Result<()> {
        let packet = names_wire::seal(
            &self.peer,
            &self.runtime.identity.device().device_id,
            message,
        )
        .unwrap();
        self.runtime.receive(&packet)
    }

    fn batch(&mut self, counter: u64, next: Option<String>) {
        self.receive(NameMessage::Batch {
            records: vec![NameRecord {
                key: "channel:general".into(),
                name: Some("Existing".into()),
                version: NameVersion {
                    counter,
                    actor: self.peer.device().device_id.clone(),
                },
            }],
            next,
        })
        .unwrap();
    }

    fn sync(&mut self) {
        self.runtime.names_last_pull = None;
        self.runtime.transport.sent_packets.clear();
        self.runtime.sync_names().unwrap();
    }

    fn restart(&mut self) {
        self.runtime = DeviceLinkRuntime::open(self.shared.clone(), self.store.clone()).unwrap();
    }
}

#[test]
fn matching_saved_names_stop_full_pulls_until_a_local_write() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    fixture.batch(20, None);
    fixture
        .receive(NameMessage::Saved {
            digest: fixture.runtime.names.digest(),
        })
        .unwrap();
    fixture.sync();
    assert!(fixture.runtime.transport.sent_packets.is_empty());
    fixture
        .runtime
        .rename_chat("channel:general", "New")
        .unwrap();
    fixture.sync();
    assert_eq!(fixture.runtime.transport.sent_packets.len(), 1);
    fixture
        .receive(NameMessage::Saved {
            digest: fixture.runtime.names.digest(),
        })
        .unwrap();
    fixture
        .receive(NameMessage::Request { after: None })
        .unwrap();
    assert!(!fixture.runtime.chat_names_snapshot().unwrap().pending);
    fixture.sync();
    assert!(fixture.runtime.transport.sent_packets.is_empty());
}

#[test]
fn a_new_linked_writer_waits_for_all_pages_then_uses_the_imported_clock() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    for result in [
        fixture.runtime.rename_chat("channel:general", "Too early"),
        fixture.runtime.reset_chat_name("channel:general"),
    ] {
        assert_eq!(result.unwrap_err().kind, ChatNameErrorKind::Unavailable);
    }
    fixture.batch(20, Some("channel:general".into()));
    fixture.restart();
    assert_eq!(
        fixture
            .runtime
            .rename_chat("channel:general", "Still early")
            .unwrap_err()
            .kind,
        ChatNameErrorKind::Unavailable
    );
    fixture
        .receive(NameMessage::Batch {
            records: vec![],
            next: None,
        })
        .unwrap();
    fixture
        .runtime
        .rename_chat("channel:general", "Accepted")
        .unwrap();
    let saved = fixture.runtime.names.page(None).pop().unwrap();
    assert_eq!(saved.version.counter, 21);
    fixture.restart();
    assert_eq!(
        fixture.runtime.chat_names_snapshot().unwrap().entries[0].name,
        "Accepted"
    );
    fixture.runtime.reset_chat_name("channel:general").unwrap();
    assert!(fixture
        .runtime
        .chat_names_snapshot()
        .unwrap()
        .entries
        .is_empty());
}

#[test]
fn an_empty_initial_pull_enables_offline_writes_across_restart() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    fixture
        .receive(NameMessage::Batch {
            records: vec![],
            next: None,
        })
        .unwrap();
    fixture.restart();
    fixture
        .runtime
        .rename_chat("channel:new", "Offline")
        .unwrap();
    assert_eq!(
        fixture.runtime.chat_names_snapshot().unwrap().entries[0].name,
        "Offline"
    );
}

#[test]
fn a_saved_digest_cannot_replace_the_initial_pull() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    fixture
        .receive(NameMessage::Saved {
            digest: fixture.runtime.names.digest(),
        })
        .unwrap();
    assert!(fixture.runtime.chat_names_snapshot().unwrap().pending);
    fixture.sync();
    assert_eq!(fixture.runtime.transport.sent_packets.len(), 1);
    fixture
        .receive(NameMessage::Batch {
            records: vec![],
            next: None,
        })
        .unwrap();
    fixture.sync();
    assert!(fixture.runtime.transport.sent_packets.is_empty());
    assert!(!fixture.runtime.chat_names_snapshot().unwrap().pending);
}

#[test]
fn a_refused_initial_save_neither_acknowledges_nor_enables_writes() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let fault = fixture.store.refuse_chat_name_writes();
    fixture.runtime.transport.sent_packets.clear();
    let result = fixture.receive(NameMessage::Batch {
        records: vec![],
        next: None,
    });
    assert_eq!(result.unwrap_err().kind, DeviceLinkErrorKind::Storage);
    assert!(fixture.runtime.transport.sent_packets.is_empty());
    drop(fault);
    fixture.restart();
    assert_eq!(
        fixture
            .runtime
            .rename_chat("channel:new", "Too early")
            .unwrap_err()
            .kind,
        ChatNameErrorKind::Unavailable
    );
    fixture
        .receive(NameMessage::Batch {
            records: vec![],
            next: None,
        })
        .unwrap();
    fixture
        .runtime
        .rename_chat("channel:new", "Accepted")
        .unwrap();
}
