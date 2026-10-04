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
fn targeted_invitation_policy_is_durable_and_a_refused_save_retains_the_manual_invite() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let invitation = fixture.runtime.create_invite(Fixture::request()).unwrap();
    let target = hex::encode(
        ed25519_dalek::SigningKey::from_bytes(&[7; 32])
            .verifying_key()
            .to_bytes(),
    );
    let fault = fixture.store.refuse_record_writes(DM_HISTORY);
    assert!(matches!(
        fixture
            .runtime
            .authenticated_owned_invite(&invitation.invite_uri, &target),
        Err(PrivateDmRuntimeError::Persistence(_))
    ));
    assert_eq!(
        fixture
            .runtime
            .sessions
            .get(&invitation.session_id)
            .unwrap()
            .invite_uri
            .as_deref(),
        Some(invitation.invite_uri.as_str())
    );
    drop(fault);
    let uri = fixture
        .runtime
        .authenticated_owned_invite(&invitation.invite_uri, &target)
        .unwrap();
    invite_ownership::verify_offered_invite(
        &uri,
        &fixture.shared.current().unwrap().public_key_hex().unwrap(),
        &target,
    )
    .unwrap();
    assert!(fixture
        .runtime
        .authenticated_owned_invite(&uri, &"a".repeat(64))
        .is_err());
    fixture.runtime = PrivateDmRuntime::from_shared_node(
        fixture.shared.clone(),
        fixture.attachments.clone(),
        Some(fixture.store.clone()),
    );
    fixture.runtime.rehydrate();
    let session = fixture
        .runtime
        .sessions
        .get(&invitation.session_id)
        .unwrap();
    assert_eq!(session.expected_invitee().unwrap(), Some(target));
    assert_eq!(session.invite_uri.as_deref(), Some(uri.as_str()));
}

#[test]
fn real_moss_keys_join_a_targeted_dm_and_pending_recovery_keeps_the_authenticated_package() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let _identities = crate::moss_ffi::replace_test_keystore(None);
    let mut creator = Fixture::new();
    let mut target = Fixture::new();
    let target_node = target.shared.acquire(0, None).unwrap();
    let target_id = target_node.public_key_hex().unwrap();
    let invitation = creator.runtime.create_invite(Fixture::request()).unwrap();
    let uri = creator
        .runtime
        .authenticated_owned_invite(&invitation.invite_uri, &target_id)
        .unwrap();
    let mut outsider = Fixture::new();
    assert!(matches!(
        outsider.runtime.accept_invite(Fixture::join_request(&uri)),
        Err(PrivateDmRuntimeError::InvalidInvite(_))
    ));
    assert!(outsider.shared.current().is_none());
    assert!(outsider
        .runtime
        .list_sessions()
        .unwrap()
        .sessions
        .is_empty());
    target
        .runtime
        .accept_invite(Fixture::join_request(&uri))
        .unwrap();
    let pending = target
        .runtime
        .sessions
        .get(&invitation.session_id)
        .unwrap()
        .pending_key_package
        .clone()
        .unwrap();
    assert!(matches!(
        decode_json::<ControlEnvelope>(&pending).unwrap(),
        ControlEnvelope::AuthenticatedKeyPackage { .. }
    ));
    assert!(target
        .runtime
        .join_recovery(&invitation.session_id)
        .unwrap()
        .key_package
        .is_some());
    let owner = creator
        .runtime
        .sessions
        .get_mut(&invitation.session_id)
        .unwrap();
    owner.handle_control(pending).unwrap();
    assert_eq!(owner.peer_moss_id.as_deref(), Some(target_id.as_str()));
    let welcome = owner.pending_welcome.clone().unwrap();
    let invitee = target
        .runtime
        .sessions
        .get_mut(&invitation.session_id)
        .unwrap();
    invitee.handle_control(welcome).unwrap();
    assert!(invitee.crypto.is_ready());
    assert!(invitee.peer_joined);
    assert!(invitee.pending_key_package.is_none());
    target.shared.release();
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
fn targeted_creation_binds_before_returning_and_discards_invalid_targets() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    assert!(fixture
        .runtime
        .create_targeted_invite(Fixture::request(), "invalid target")
        .is_err());
    assert!(fixture.runtime.list_sessions().unwrap().sessions.is_empty());
    assert!(fixture.shared.current().is_none());
    let target = "b".repeat(64);
    let created = fixture
        .runtime
        .create_targeted_invite(Fixture::request(), &target)
        .unwrap();
    assert_eq!(
        fixture
            .runtime
            .sessions
            .get(&created.session_id)
            .unwrap()
            .expected_invitee()
            .unwrap(),
        Some(target)
    );
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
