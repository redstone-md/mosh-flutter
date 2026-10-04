use super::*;
use crate::moss_ffi::{drain_received_messages, fail_next_test_publish, MOSS_TEST_LOCK};

use crate::test_temp_directory::TempDirectory;

#[path = "retry_authentication_tests.rs"]
mod retry_authentication;

#[path = "durability_tests/welcome_offer_authentication.rs"]
mod welcome_offer_authentication;

struct Fixture {
    store: Arc<Persistence>,
    runtime: PrivateGroupRuntime,
    id: String,
    directory: TempDirectory,
}

impl Fixture {
    fn empty() -> Self {
        drain_received_messages();
        let directory = TempDirectory::new("mosh-private-group-durable");
        let store = Arc::new(
            Persistence::open_with_dek(&directory.path().join("history.redb"), [57; 32]).unwrap(),
        );
        let attachments = Arc::new(AttachmentStore::new(directory.path()).unwrap());
        let moss = Arc::new(MossFfiRuntime::load_default().unwrap());
        let runtime = PrivateGroupRuntime::from_shared(moss, attachments, Some(store.clone()));
        Self {
            store,
            runtime,
            id: String::new(),
            directory,
        }
    }

    fn new() -> Self {
        let mut fixture = Self::empty();
        fixture.id = fixture
            .runtime
            .create_group(CreateGroupRequest {
                label: Some("Durable Group".into()),
                display_name: "Alice".into(),
                listen_port: 42247,
                static_peer: None,
                org_pubkey: None,
            })
            .unwrap()
            .group_id;
        fixture
    }

    fn join(&mut self, invite: &str, display_name: &str) {
        self.id = self
            .runtime
            .join_group(JoinGroupRequest {
                invite_uri: invite.into(),
                display_name: display_name.into(),
                org_pubkey: None,
                listen_port: 42247,
                static_peer: None,
            })
            .unwrap()
            .group_id;
    }

    fn deliver_welcome(&mut self, admin: &mut MlsSessionCrypto) {
        let session = self.runtime.groups.get_mut(&self.id).unwrap();
        let key_package = session.crypto.key_package_bytes().unwrap();
        let outcome = admin.add_members(&[key_package.as_slice()]).unwrap();
        let welcome = ControlEnvelope::Welcome {
            group_id: self.id.clone(),
            for_participant_id: session.participant_id.clone(),
            from_fingerprint: admin.fingerprint(),
            welcome_b64: encode(&outcome.welcome_bytes),
            tree_b64: encode(&outcome.tree_bytes),
            commit_b64: encode(&outcome.commit_bytes),
        };
        inbox::deliver(MossReceivedMessage {
            channel: session.control_channel.clone(),
            payload: serde_json::to_vec(&welcome).unwrap(),
        });
    }

    fn restart(&mut self) {
        let attachments = Arc::new(AttachmentStore::new(self.directory.path()).unwrap());
        let moss = Arc::new(MossFfiRuntime::load_default().unwrap());
        self.runtime =
            PrivateGroupRuntime::from_shared(moss, attachments, Some(self.store.clone()));
        self.runtime.rehydrate();
    }

    fn rejoining() -> Self {
        let mut fixture = Self::empty();
        let mut admin = MlsSessionCrypto::new("Alice").unwrap();
        admin.create_group().unwrap();
        let invite = build_invite_uri(
            &admin.random_token("mesh").unwrap(),
            &admin.random_token("group").unwrap(),
            &admin.fingerprint(),
            &None,
        );
        fixture.join(&invite, "Bob");
        fixture.deliver_welcome(&mut admin);
        assert_eq!(fixture.runtime.poll(&fixture.id).unwrap().member_count, 2);

        let refused_close = fixture.store.refuse_record_writes(GROUP_HISTORY);
        assert!(fixture.runtime.close(&fixture.id).unwrap().closed);
        drop(refused_close);
        admin.remove_members_by_identity("Bob").unwrap();
        fixture.join(&invite, "Bob rejoined");
        fixture.deliver_welcome(&mut admin);
        fixture
    }

    fn assert_accepted_group_restores(&mut self) {
        // Restart before a pending retry: both rows must still describe the
        // last accepted join, even though this rejoin was refused.
        self.restart();
        let recovered = self
            .runtime
            .poll(&self.id)
            .expect("refused rejoin must preserve a restorable accepted group");
        assert_eq!(recovered.member_count, 2);
        assert_eq!(recovered.display_name, "Bob");
    }
}

fn assert_attachment(snapshot: &GroupSnapshot, attachment_id: &str) {
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
    let fault = fixture.store.refuse_message_writes(GROUP_HISTORY);
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
    let groups = fixture.runtime.list().unwrap().groups;
    assert_attachment(&groups[0], &sent.attachment_id);
    drop(fault);
    fixture.runtime.poll(&fixture.id).unwrap();
    let saved = fixture.store.list_group_messages(&fixture.id).unwrap();
    assert_eq!(saved.len(), 1);
    fixture.restart();
    let restored = fixture.runtime.poll(&fixture.id).unwrap();
    assert_attachment(&restored, &sent.attachment_id);
}

#[test]
fn refused_rejoin_record_keeps_the_last_accepted_group_restorable() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::rejoining();
    let refused_record = fixture.store.refuse_record_writes(GROUP_HISTORY);
    let volatile = fixture.runtime.poll(&fixture.id).unwrap();
    assert_eq!(volatile.display_name, "Bob rejoined");
    drop(refused_record);
    fixture.assert_accepted_group_restores();
}

#[test]
fn refused_rejoin_snapshot_rolls_back_the_new_group_record() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::rejoining();
    let refused_snapshot = fixture.store.refuse_group_snapshot_writes();
    let volatile = fixture.runtime.poll(&fixture.id).unwrap();
    assert_eq!(volatile.display_name, "Bob rejoined");
    drop(refused_snapshot);
    fixture.assert_accepted_group_restores();
}

#[test]
fn refused_storage_does_not_publish_and_retains_a_deliberate_retry() {
    let _lock = MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let mut fixture = Fixture::new();
    let fault = fixture.store.refuse_message_writes(GROUP_HISTORY);
    let _publication = fail_next_test_publish("publication was deferred");
    let error = fixture
        .runtime
        .send(&fixture.id, "durable first".into())
        .unwrap_err();
    assert!(matches!(error, PrivateGroupError::Persistence(_)));
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
        .get_outbound_attempt(GROUP_HISTORY.outbound_scope, &fixture.id, &message_id)
        .unwrap()
        .is_none());
}
