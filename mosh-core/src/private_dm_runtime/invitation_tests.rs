use super::state_tests::{accept, connect, ALICE_ID, BOB_ID};
use super::transport::memory::MemoryNet;
use super::*;
use crate::test_temp_directory::TempDirectory;

struct Fixture {
    runtime: PrivateDmRuntime,
    net: Arc<MemoryNet>,
    store: Arc<Persistence>,
    attachments: Arc<AttachmentStore>,
    _directory: TempDirectory,
}

#[path = "invitation_recovery_tests.rs"]
mod recovery;

#[path = "invitation_legacy_tests.rs"]
mod legacy;

impl Fixture {
    fn new() -> Self {
        let directory = TempDirectory::new("mosh-saved-invitations");
        let store = Arc::new(
            Persistence::open_with_dek(&directory.path().join("history.redb"), [81; 32]).unwrap(),
        );
        let attachments = Arc::new(AttachmentStore::new(directory.path()).unwrap());
        let net = MemoryNet::new();
        let runtime = PrivateDmRuntime::with_transport(
            net.endpoint(ALICE_ID),
            attachments.clone(),
            Some(store.clone()),
        );
        Self {
            runtime,
            net,
            store,
            attachments,
            _directory: directory,
        }
    }

    fn create(&mut self) -> InviteCreated {
        self.runtime
            .create_pending_invite(StartSessionRequest {
                display_name: "Alice".into(),
                listen_port: 0,
                static_peer: None,
            })
            .unwrap()
    }

    fn restart(&mut self) {
        self.runtime = PrivateDmRuntime::with_transport(
            self.net.endpoint(ALICE_ID),
            self.attachments.clone(),
            Some(self.store.clone()),
        );
        self.runtime.rehydrate();
    }

    fn bob(&self) -> PrivateDmRuntime {
        self.net.link_both(ALICE_ID, BOB_ID, PeerTransport::Direct);
        PrivateDmRuntime::with_transport(self.net.endpoint(BOB_ID), self.attachments.clone(), None)
    }
}

#[test]
fn saved_invitations_are_independent_hidden_and_survive_restart() {
    let mut fixture = Fixture::new();
    let first = fixture.create();
    let second = fixture.create();
    assert_ne!(first.session_id, second.session_id);
    assert!(fixture.runtime.list_sessions().unwrap().sessions.is_empty());
    fixture.restart();
    assert_eq!(fixture.runtime.list_pending_invites().unwrap().len(), 2);
    assert!(fixture.runtime.list_sessions().unwrap().sessions.is_empty());
    fixture.runtime.open_session(&first.session_id).unwrap();
    fixture.runtime.open_session(&first.session_id).unwrap();
    fixture.restart();
    let visible = fixture.runtime.list_sessions().unwrap().sessions;
    assert_eq!(visible.len(), 1);
    assert_eq!(visible[0].session_id, first.session_id);
    assert_eq!(
        fixture.runtime.list_pending_invites().unwrap()[0].session_id,
        second.session_id
    );
}

#[test]
fn rotation_preserves_address_visibility_and_other_invitations() {
    let mut fixture = Fixture::new();
    let first = fixture.create();
    let second = fixture.create();
    fixture.runtime.open_session(&first.session_id).unwrap();
    let rotated = fixture.runtime.replace_invite(&first.session_id).unwrap();
    assert_eq!(rotated.session_id, first.session_id);
    assert_eq!(rotated.mesh_id, first.mesh_id);
    assert_ne!(rotated.invite_uri, first.invite_uri);
    fixture.restart();
    assert_eq!(fixture.runtime.list_sessions().unwrap().sessions.len(), 1);
    assert_eq!(
        fixture.runtime.list_pending_invites().unwrap()[0].invite_uri,
        second.invite_uri
    );
    assert_eq!(
        fixture
            .runtime
            .poll_session(&first.session_id)
            .unwrap()
            .invite_uri,
        Some(rotated.invite_uri)
    );
}

#[test]
fn refused_rotation_and_open_keep_the_durable_previous_state() {
    let mut fixture = Fixture::new();
    let invitation = fixture.create();
    let fault = fixture.store.refuse_record_writes(DM_HISTORY);
    assert!(matches!(
        fixture.runtime.replace_invite(&invitation.session_id),
        Err(PrivateDmRuntimeError::Persistence(_))
    ));
    assert!(matches!(
        fixture.runtime.open_session(&invitation.session_id),
        Err(PrivateDmRuntimeError::Persistence(_))
    ));
    assert_eq!(
        fixture.runtime.list_pending_invites().unwrap()[0].invite_uri,
        invitation.invite_uri
    );
    assert!(fixture.runtime.list_sessions().unwrap().sessions.is_empty());
    drop(fault);
    fixture.restart();
    let mut bob = fixture.bob();
    accept(&mut bob, &invitation);
    connect(&mut fixture.runtime, &mut bob, &invitation.session_id);
    assert!(
        !fixture
            .runtime
            .poll_session(&invitation.session_id)
            .unwrap()
            .invite_available
    );
}

#[test]
fn old_and_tokenless_admission_cannot_consume_a_rotated_invitation() {
    let mut fixture = Fixture::new();
    let old = fixture.create();
    let current = fixture.runtime.replace_invite(&old.session_id).unwrap();
    let mut bob = fixture.bob();
    accept(&mut bob, &old);
    fixture.runtime.service();
    assert!(fixture.runtime.list_sessions().unwrap().sessions.is_empty());
    assert_eq!(fixture.runtime.list_pending_invites().unwrap().len(), 1);
    let pending = bob
        .session_ref(&old.session_id)
        .unwrap()
        .pending_key_package
        .clone()
        .unwrap();
    let ControlEnvelope::InvitationKeyPackage { payload_b64, .. } = decode_json(&pending).unwrap()
    else {
        panic!("token wrapper");
    };
    assert!(fixture
        .runtime
        .session_mut(&old.session_id)
        .unwrap()
        .handle_control(decode(&payload_b64).unwrap())
        .is_err());
    bob.close_session(&old.session_id).unwrap();
    accept(&mut bob, &current);
    connect(&mut fixture.runtime, &mut bob, &current.session_id);
    assert_eq!(fixture.runtime.list_sessions().unwrap().sessions.len(), 1);
}

#[test]
fn first_admission_is_durable_without_messages_and_refuses_later_rotation() {
    let mut fixture = Fixture::new();
    let invitation = fixture.create();
    let mut bob = fixture.bob();
    accept(&mut bob, &invitation);
    fixture.runtime.service();
    assert_eq!(fixture.runtime.list_sessions().unwrap().sessions.len(), 1);
    fixture.restart();
    assert!(fixture.runtime.list_pending_invites().unwrap().is_empty());
    assert!(
        !fixture
            .runtime
            .poll_session(&invitation.session_id)
            .unwrap()
            .invite_available
    );
    assert!(fixture
        .runtime
        .replace_invite(&invitation.session_id)
        .is_err());
    let session = fixture.runtime.session_ref(&invitation.session_id).unwrap();
    assert_eq!(session.crypto.member_count(), 2);
    assert!(session.peer_joined);
}

#[test]
fn refused_admission_does_not_consume_or_publish_welcome() {
    let mut fixture = Fixture::new();
    let invitation = fixture.create();
    let mut bob = fixture.bob();
    accept(&mut bob, &invitation);
    let fault = fixture.store.refuse_dm_snapshot_writes();
    fixture.runtime.service();
    assert!(fixture.runtime.list_sessions().unwrap().sessions.is_empty());
    assert_eq!(
        fixture
            .runtime
            .session_ref(&invitation.session_id)
            .unwrap()
            .crypto
            .member_count(),
        1
    );
    assert!(
        !bob.poll_session(&invitation.session_id)
            .unwrap()
            .invite_available
    );
    assert!(!bob
        .session_ref(&invitation.session_id)
        .unwrap()
        .crypto
        .is_ready());
    drop(fault);
    fixture.restart();
    bob.session_mut(&invitation.session_id)
        .unwrap()
        .last_handshake_send_ms = 0;
    connect(&mut fixture.runtime, &mut bob, &invitation.session_id);
    assert_eq!(fixture.runtime.list_sessions().unwrap().sessions.len(), 1);
}
