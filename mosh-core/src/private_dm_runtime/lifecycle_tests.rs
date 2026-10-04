use super::*;
use crate::moss_ffi::{fail_next_test_publish, no_peers_next_test_publish, MOSS_TEST_LOCK};
use crate::shared_node::SharedMossNode;
use crate::test_temp_directory::TempDirectory;

struct Fixture {
    runtime: PrivateDmRuntime,
    shared: Arc<SharedMossNode>,
    store: Arc<Persistence>,
    attachments: Arc<AttachmentStore>,
    directory: TempDirectory,
}

impl Fixture {
    fn new() -> Self {
        crate::moss_ffi::drain_received_messages();
        let directory = TempDirectory::new("mosh-dm-lifecycle");
        let store = Arc::new(
            Persistence::open_with_dek(&directory.path().join("history.redb"), [79; 32]).unwrap(),
        );
        let attachments = Arc::new(AttachmentStore::new(directory.path()).unwrap());
        let shared = SharedMossNode::new(Arc::new(MossFfiRuntime::load_default().unwrap()));
        let runtime = PrivateDmRuntime::from_shared_node(
            shared.clone(),
            attachments.clone(),
            Some(store.clone()),
        );
        Self {
            runtime,
            shared,
            store,
            attachments,
            directory,
        }
    }

    fn request() -> StartSessionRequest {
        StartSessionRequest {
            display_name: "Alice".into(),
            listen_port: 0,
            static_peer: None,
        }
    }

    fn join_request(uri: &str) -> AcceptInviteRequest {
        AcceptInviteRequest {
            invite_uri: uri.into(),
            display_name: "Bob".into(),
            listen_port: 0,
            static_peer: None,
        }
    }

    fn assert_refused_creation_stays_absent(&mut self) {
        assert!(self.runtime.list_sessions().unwrap().sessions.is_empty());
        assert!(self.shared.current().is_none());
        self.runtime = PrivateDmRuntime::from_shared_node(
            self.shared.clone(),
            self.attachments.clone(),
            Some(self.store.clone()),
        );
        self.runtime.rehydrate();
        assert!(self.runtime.list_sessions().unwrap().sessions.is_empty());
        assert!(self.store.list_sessions().unwrap().is_empty());
        assert!(self.directory.path().is_dir());
        self.runtime.create_invite(Self::request()).unwrap();
        assert_eq!(self.runtime.list_sessions().unwrap().sessions.len(), 1);
    }
}

#[test]
fn refused_creator_record_never_leaves_a_session_or_room() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let fault = fixture.store.refuse_record_writes(DM_HISTORY);
    assert!(matches!(
        fixture.runtime.create_invite(Fixture::request()),
        Err(PrivateDmRuntimeError::Persistence(_))
    ));
    drop(fault);
    fixture.assert_refused_creation_stays_absent();
}

#[test]
fn refused_creator_snapshot_never_leaves_a_session_or_room() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let fault = fixture.store.refuse_dm_snapshot_writes();
    assert!(matches!(
        fixture.runtime.create_invite(Fixture::request()),
        Err(PrivateDmRuntimeError::Persistence(_))
    ));
    drop(fault);
    fixture.assert_refused_creation_stays_absent();
}

#[test]
fn failed_first_key_package_releases_room_and_allows_same_invite_retry() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let uri =
        "mosh://invite?mesh=retry-mesh&session=retry-session#fp=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
    let fault = fail_next_test_publish("first key package refused");
    assert!(matches!(
        fixture.runtime.accept_invite(Fixture::join_request(uri)),
        Err(PrivateDmRuntimeError::Moss(_))
    ));
    drop(fault);
    assert!(fixture.runtime.list_sessions().unwrap().sessions.is_empty());
    assert!(fixture.shared.current().is_none());
    fixture
        .runtime
        .accept_invite(Fixture::join_request(uri))
        .unwrap();
    assert_eq!(fixture.runtime.list_sessions().unwrap().sessions.len(), 1);
}

#[test]
fn no_peers_does_not_refuse_repeatable_key_package_admission() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let uri =
        "mosh://invite?mesh=no-peers-mesh&session=no-peers-session#fp=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
    let _fault = no_peers_next_test_publish();
    fixture
        .runtime
        .accept_invite(Fixture::join_request(uri))
        .unwrap();
    assert_eq!(fixture.runtime.list_sessions().unwrap().sessions.len(), 1);
}
