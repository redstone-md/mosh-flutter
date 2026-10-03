use super::*;
use crate::moss_ffi::{drain_received_messages, MOSS_TEST_LOCK};
use crate::test_temp_directory::TempDirectory;

fn request() -> CreateGroupRequest {
    CreateGroupRequest {
        label: Some("Durable Group".into()),
        display_name: "Alice".into(),
        listen_port: 42247,
        static_peer: None,
        org_pubkey: None,
    }
}

struct Fixture {
    store: Arc<Persistence>,
    shared: Arc<SharedMossNode>,
    attachments: Arc<AttachmentStore>,
    runtime: PrivateGroupRuntime,
    _directory: TempDirectory,
}

impl Fixture {
    fn new() -> Self {
        drain_received_messages();
        let directory = TempDirectory::new("mosh-group-creation");
        let store = Arc::new(
            Persistence::open_with_dek(&directory.path().join("history.redb"), [57; 32]).unwrap(),
        );
        let attachments = Arc::new(AttachmentStore::new(directory.path()).unwrap());
        let shared = SharedMossNode::new(Arc::new(MossFfiRuntime::load_default().unwrap()));
        let runtime = PrivateGroupRuntime::from_shared_node(
            shared.clone(),
            attachments.clone(),
            Some(store.clone()),
        );
        Self {
            store,
            shared,
            attachments,
            runtime,
            _directory: directory,
        }
    }

    fn restart(&mut self) {
        self.runtime = PrivateGroupRuntime::from_shared_node(
            self.shared.clone(),
            self.attachments.clone(),
            Some(self.store.clone()),
        );
        self.runtime.rehydrate();
    }
}

#[test]
fn refused_creation_releases_its_room_and_never_appears_after_repair() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let fault = fixture.store.refuse_group_snapshot_writes();
    let error = fixture.runtime.create_group(request()).unwrap_err();
    assert!(matches!(error, PrivateGroupError::Persistence(_)));
    drop(fault);
    assert!(fixture.runtime.list().unwrap().groups.is_empty());
    assert!(fixture.shared.current().is_none());
    fixture.restart();
    assert!(fixture.runtime.list().unwrap().groups.is_empty());
    fixture
        .runtime
        .create_group(request())
        .expect("a deliberate new creation succeeds");
    assert_eq!(fixture.runtime.list().unwrap().groups.len(), 1);
}

#[test]
fn unrelated_refused_history_does_not_refuse_new_creation() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let existing = fixture.runtime.create_group(request()).unwrap().group_id;
    let fault = fixture.store.refuse_message_writes(GROUP_HISTORY);
    assert!(matches!(
        fixture.runtime.send(&existing, "refused history".into()),
        Err(PrivateGroupError::Persistence(_))
    ));
    let created = fixture
        .runtime
        .create_group(request())
        .expect("creation writes only its own record and snapshot");
    drop(fault);
    fixture.restart();
    let groups = fixture.runtime.list().unwrap().groups;
    assert_eq!(groups.len(), 2);
    assert!(groups
        .iter()
        .any(|group| group.group_id == created.group_id));
}
