//! A channel installation for tests that move frames between two of them.
use super::*;
use crate::test_temp_directory::TempDirectory;

pub(super) const ROOM: &str = "channel-test";

/// One installation joined to [`ROOM`], with its own database and keystore.
pub(super) struct Fixture {
    pub(super) runtime: ChannelRuntime,
    pub(super) store: Arc<Persistence>,
    directory: TempDirectory,
}
impl Fixture {
    pub(super) fn new() -> Self {
        drain_received_messages();
        let directory = TempDirectory::new("channel-fixture");
        let store = Arc::new(
            Persistence::open_with_dek(&directory.path().join("history"), [39; 32]).unwrap(),
        );
        let _identity = crate::moss_ffi::replace_test_keystore(Some(store.clone()));
        let mut runtime = ChannelRuntime::from_shared(
            Arc::new(MossFfiRuntime::load_default().unwrap()),
            Arc::new(AttachmentStore::new(directory.path()).unwrap()),
            Some(store.clone()),
        );
        runtime
            .join(JoinChannelRequest {
                name: ROOM.into(),
                display_name: "Same name".into(),
                listen_port: 0,
                static_peer: None,
            })
            .unwrap();
        Self {
            runtime,
            store,
            directory,
        }
    }
    pub(super) fn restart(&mut self) {
        let _identity = crate::moss_ffi::replace_test_keystore(Some(self.store.clone()));
        self.runtime = ChannelRuntime::from_shared(
            Arc::new(MossFfiRuntime::load_default().unwrap()),
            Arc::new(AttachmentStore::new(self.directory.path()).unwrap()),
            Some(self.store.clone()),
        );
        self.runtime.rehydrate();
    }
    pub(super) fn deliver(&mut self, message: MossReceivedMessage) {
        inbox::deliver(message);
        self.runtime.poll(ROOM).unwrap();
    }
}
