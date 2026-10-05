//! Deterministic packet ordering through two authenticated runtime registers.
//! The process-global Moss identity requires independent processes for network
//! integration; these tests deliver captured packets to control each cadence.
use super::*;

struct Pair {
    left: DeviceLinkRuntime,
    right: DeviceLinkRuntime,
    shared: Arc<SharedMossNode>,
    store: Arc<Persistence>,
    _directory: TempDirectory,
}

impl Pair {
    fn new() -> Self {
        let fixture = Fixture::new();
        let right = DeviceLinkRuntime {
            deletion_last_pull: None,
            deletion_digests: Default::default(),
            deletion_pages: Default::default(),
            deletion_fragments: Default::default(),
            names: fixture.peer.chat_names().unwrap(),
            identity: fixture.peer,
            transport: LinkTransport::new(fixture.shared.clone()).unwrap(),
            exchange: None,
            phase: DeviceLinkPhase::Idle,
            error: None,
            delivery_last_send: None,
            delivery_started: Instant::now(),
            roster_last_send: None,
            names_last_pull: None,
            names_peer_digests: Default::default(),
            names_initial_pulls: Default::default(),
            names_pending_pages: Default::default(),
        };
        Self {
            left: fixture.runtime,
            right,
            shared: fixture.shared,
            store: fixture.store,
            _directory: fixture._directory,
        }
    }

    /// One elapsed cadence, followed by all replies before the next cadence.
    fn tick(&mut self) -> usize {
        self.left.names_last_pull = None;
        self.right.names_last_pull = None;
        self.left.sync_names().unwrap();
        self.right.sync_names().unwrap();
        let mut sent = 0;
        for _ in 0..8 {
            let left = std::mem::take(&mut self.left.transport.sent_packets);
            let right = std::mem::take(&mut self.right.transport.sent_packets);
            if left.is_empty() && right.is_empty() {
                return sent;
            }
            sent += left.len() + right.len();
            for packet in left {
                self.right.receive(&packet).unwrap();
            }
            self.right.sync_names().unwrap();
            for packet in right {
                self.left.receive(&packet).unwrap();
            }
            self.left.sync_names().unwrap();
        }
        panic!("name replies did not settle within one cadence");
    }

    fn settle(&mut self) {
        for _ in 0..6 {
            if self.tick() == 0 {
                assert_eq!(self.tick(), 0);
                assert!(!self.left.chat_names_snapshot().unwrap().pending);
                assert!(!self.right.chat_names_snapshot().unwrap().pending);
                return;
            }
        }
        panic!("name registers continued sending after matching");
    }

    fn restart_left(&mut self) {
        self.left = DeviceLinkRuntime::open(self.shared.clone(), self.store.clone()).unwrap();
    }
}

#[test]
fn matching_registers_stop_sending_again_after_only_one_runtime_restarts() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut pair = Pair::new();
    pair.settle();
    pair.left
        .rename_chat("channel:general", "Existing")
        .unwrap();
    pair.settle();
    pair.restart_left();
    pair.settle();
    assert_eq!(pair.left.names.name("channel:general"), Some("Existing"));
    assert_eq!(pair.right.names.name("channel:general"), Some("Existing"));
}

#[test]
fn either_acknowledged_writer_can_rename_without_endless_reciprocal_pulls() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut pair = Pair::new();
    pair.settle();
    pair.left.rename_chat("channel:general", "First").unwrap();
    pair.settle();
    assert_eq!(pair.right.names.name("channel:general"), Some("First"));
    pair.right.rename_chat("channel:general", "Second").unwrap();
    pair.settle();
    assert_eq!(pair.left.names.name("channel:general"), Some("Second"));
    pair.left.reset_chat_name("channel:general").unwrap();
    pair.settle();
    assert_eq!(pair.right.names.name("channel:general"), None);
}
