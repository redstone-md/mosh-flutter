use super::*;
use crate::message_deletion::{
    cipher, fragments, protocol::DeletionMessage, shared, DeleteScope, DeletionStatus,
};
use crate::test_temp_directory::TempDirectory;

const ROOM: &str = "deletion-test";
#[path = "deletion_names.rs"]
mod names;

struct Fixture {
    runtime: ChannelRuntime,
    store: Arc<Persistence>,
    directory: TempDirectory,
}
impl Fixture {
    fn new() -> Self {
        let directory = TempDirectory::new("channel-deletion");
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
    fn restart(&mut self) {
        let _identity = crate::moss_ffi::replace_test_keystore(Some(self.store.clone()));
        self.runtime = ChannelRuntime::from_shared(
            Arc::new(MossFfiRuntime::load_default().unwrap()),
            Arc::new(AttachmentStore::new(self.directory.path()).unwrap()),
            Some(self.store.clone()),
        );
        self.runtime.rehydrate();
    }
    fn deliver(&mut self, message: MossReceivedMessage) {
        inbox::deliver(message);
        self.runtime.poll(ROOM).unwrap();
    }
    fn deletion_status(&mut self) -> DeletionStatus {
        self.runtime.poll(ROOM).unwrap().messages[0]
            .metadata
            .as_ref()
            .unwrap()
            .deletion
            .as_ref()
            .unwrap()
            .status
    }
    fn identity(&self) -> crate::device_link::identity::DeviceIdentity {
        let peer = &self.runtime.channels.get(ROOM).unwrap().device_fingerprint;
        crate::device_link::identity::DeviceIdentity::open(self.store.clone(), peer).unwrap()
    }
}

fn text(sender: &mut Fixture, receiver: &mut Fixture) -> String {
    let sent = sender.runtime.send(ROOM, "delete this".into()).unwrap();
    let session = sender.runtime.channels.get(ROOM).unwrap();
    let message = session.publishable_message(&session.messages[0]);
    receiver.deliver(MossReceivedMessage {
        channel: session.topic.clone(),
        payload: serde_json::to_vec(&message).unwrap(),
    });
    sent.message_id
}

fn deletion(sender: &mut Fixture, receiver: &mut Fixture, message: DeletionMessage) {
    let session = sender.runtime.channels.get(ROOM).unwrap();
    for message in fragments::split(&message).unwrap() {
        let frame = cipher::seal_channel(
            &session.deletions.context,
            session.node.identity_signer().unwrap(),
            &message,
        )
        .unwrap();
        receiver.deliver(MossReceivedMessage {
            channel: session.blob_topic.clone(),
            payload: serde_json::to_vec(&ChannelBlobEnvelope::MessageDeletion { frame }).unwrap(),
        });
    }
}

fn state(sender: &mut Fixture, receiver: &mut Fixture) {
    let session = sender.runtime.channels.get(ROOM).unwrap();
    let authority = session.deletion_authority().unwrap();
    deletion(
        sender,
        receiver,
        shared::page(&session.deletions, None, &authority),
    );
}

#[test]
fn channel_deletion_checks_signatures_and_waits_for_another_participant() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let (mut author, mut reader) = (Fixture::new(), Fixture::new());
    let id = text(&mut author, &mut reader);
    assert!(reader
        .runtime
        .delete_messages(ROOM, std::slice::from_ref(&id), DeleteScope::ForEveryone)
        .is_err());
    author
        .runtime
        .delete_messages(ROOM, &[id], DeleteScope::ForEveryone)
        .unwrap();
    state(&mut author, &mut reader);
    assert_eq!(reader.runtime.poll(ROOM).unwrap().messages[0].body, "");
    state(&mut reader, &mut author);
    let snapshot = author.runtime.poll(ROOM).unwrap();
    assert_eq!(
        snapshot.messages[0]
            .metadata
            .as_ref()
            .unwrap()
            .deletion
            .as_ref()
            .unwrap()
            .status,
        DeletionStatus::Confirmed
    );
    author.restart();
    assert_eq!(author.runtime.poll(ROOM).unwrap().messages[0].body, "");
}

#[test]
fn a_returning_reader_recovers_a_deletion_before_the_original_message() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let (mut author, mut reader) = (Fixture::new(), Fixture::new());
    let sent = author.runtime.send(ROOM, "never restore".into()).unwrap();
    let session = author.runtime.channels.get(ROOM).unwrap();
    let original = MossReceivedMessage {
        channel: session.topic.clone(),
        payload: serde_json::to_vec(&session.publishable_message(&session.messages[0])).unwrap(),
    };
    author
        .runtime
        .delete_messages(ROOM, &[sent.message_id], DeleteScope::ForEveryone)
        .unwrap();
    state(&mut author, &mut reader);
    reader.deliver(original);
    assert_eq!(reader.runtime.poll(ROOM).unwrap().messages[0].body, "");
    reader.restart();
    assert_eq!(reader.runtime.poll(ROOM).unwrap().messages[0].body, "");
}

#[test]
fn identical_attachment_copies_survive_until_the_last_row_is_deleted() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut f = Fixture::new();
    let mut ids = Vec::new();
    let mut path = None;
    for _ in 0..2 {
        let sent = f
            .runtime
            .send_attachment(
                ROOM,
                "file.bin".into(),
                "application/octet-stream".into(),
                vec![42; 32],
                None,
                None,
            )
            .unwrap();
        let store = f.runtime.channels.attachment_store();
        path = Some(store.path_for(&sent.content_hash, "file.bin").unwrap());
        ids.push(sent.attachment_id);
    }
    f.runtime
        .delete_messages(ROOM, &ids[..1], DeleteScope::ForMe)
        .unwrap();
    assert!(path.as_ref().unwrap().exists());
    f.runtime
        .delete_messages(ROOM, &ids[1..], DeleteScope::ForMe)
        .unwrap();
    assert!(!path.unwrap().exists());
    assert!(f.runtime.poll(ROOM).unwrap().messages.is_empty());
}

#[test]
fn a_revoked_installation_reports_the_revoked_bridge_category() {
    use crate::device_link::{identity::DeviceIdentity, types::DeviceDescriptor};
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut f = Fixture::new();
    let sent = f.runtime.send(ROOM, "retain me".into()).unwrap();
    let peer = f
        .runtime
        .channels
        .get(ROOM)
        .unwrap()
        .device_fingerprint
        .clone();
    let mut identity = DeviceIdentity::open(f.store.clone(), &peer).unwrap();
    let other = ed25519_dalek::SigningKey::from_bytes(&[8; 32]);
    identity.record.roster = identity
        .roster()
        .extend(
            DeviceDescriptor::new(&other, &"ef".repeat(32)),
            &identity.key(),
        )
        .unwrap()
        .revoke(&identity.device().device_id, &other)
        .unwrap();
    f.store
        .put_device_link(&serde_json::to_vec(&identity.record).unwrap())
        .unwrap();
    let error = f
        .runtime
        .delete_messages(ROOM, &[sent.message_id], DeleteScope::ForEveryone)
        .expect_err("revocation must refuse deletion");
    let error = crate::api::conversation_bridge::ConversationBridgeError::from(error);
    assert_eq!(
        error.kind,
        crate::api::conversation_bridge::ConversationBridgeErrorKind::Revoked
    );
    assert_eq!(
        f.runtime.channels.get(ROOM).unwrap().messages[0].body,
        "retain me"
    );
}

fn link_accounts(source: &Fixture, destination: &Fixture) -> String {
    crate::device_link::test_support::link_accounts(source.identity(), destination.identity())
}

#[test]
fn personal_attachment_erasure_matches_an_older_own_copy_even_after_shared_erasure() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    for shared_first in [false, true] {
        let (mut source, mut legacy) = (Fixture::new(), Fixture::new());
        let sent = source
            .runtime
            .send_attachment(
                ROOM,
                "file.bin".into(),
                "application/octet-stream".into(),
                vec![42; 32],
                None,
                None,
            )
            .unwrap();
        let session = source.runtime.channels.get(ROOM).unwrap();
        let mut manifest = session.transfer.manifest_for(&sent.attachment_id).unwrap();
        manifest.origin = None;
        let envelope = ChannelBlobEnvelope::Manifest {
            from_device: session.display_name.clone(),
            from_fingerprint: session.device_fingerprint.clone(),
            manifest: Box::new(manifest.into()),
        };
        legacy.deliver(MossReceivedMessage {
            channel: session.blob_topic.clone(),
            payload: serde_json::to_vec(&envelope).unwrap(),
        });
        let user = link_accounts(&source, &legacy);
        if shared_first {
            source
                .runtime
                .delete_messages(
                    ROOM,
                    std::slice::from_ref(&sent.attachment_id),
                    DeleteScope::ForEveryone,
                )
                .unwrap();
        }
        source
            .runtime
            .delete_messages(ROOM, &[sent.attachment_id], DeleteScope::ForMe)
            .unwrap();
        let records: Vec<_> = source
            .store
            .account_deletions(&user)
            .unwrap()
            .into_iter()
            .filter(|r| r.scope == DeleteScope::ForMe)
            .collect();
        legacy
            .store
            .save_account_deletions(&user, &records)
            .unwrap();
        assert!(legacy.runtime.poll(ROOM).unwrap().messages.is_empty());
        legacy.restart();
        assert!(legacy.runtime.poll(ROOM).unwrap().messages.is_empty());
    }
}

#[test]
fn linked_channel_deletion_waits_for_a_certificate_and_another_account() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let (mut root, mut linked) = (Fixture::new(), Fixture::new());
    link_accounts(&root, &linked);
    let id = text(&mut linked, &mut root);
    assert!(
        !linked.runtime.poll(ROOM).unwrap().messages[0]
            .metadata
            .as_ref()
            .unwrap()
            .can_delete_for_everyone
    );
    assert!(linked
        .runtime
        .delete_messages(ROOM, std::slice::from_ref(&id), DeleteScope::ForEveryone)
        .is_err());
    crate::device_link::test_support::certify_device(root.identity(), linked.identity());
    linked
        .runtime
        .delete_messages(ROOM, &[id], DeleteScope::ForEveryone)
        .unwrap();
    state(&mut linked, &mut root);
    state(&mut root, &mut linked);
    assert_eq!(linked.deletion_status(), DeletionStatus::Pending);
    let mut external = Fixture::new();
    state(&mut linked, &mut external);
    state(&mut external, &mut linked);
    assert_eq!(linked.deletion_status(), DeletionStatus::Confirmed);
}

#[test]
fn a_locally_revoked_channel_device_cannot_delete_an_active_own_devices_message() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let (mut root, mut retired) = (Fixture::new(), Fixture::new());
    link_accounts(&root, &retired);
    crate::device_link::test_support::certify_device(root.identity(), retired.identity());
    text(&mut root, &mut retired);
    let target = root.runtime.poll(ROOM).unwrap().messages[0]
        .metadata
        .as_ref()
        .unwrap()
        .origin
        .clone()
        .unwrap();
    let mut identity = root.identity();
    identity.record.roster = identity
        .roster()
        .revoke(&retired.identity().device().device_id, &identity.key())
        .unwrap();
    root.store
        .put_device_link(&serde_json::to_vec(&identity.record).unwrap())
        .unwrap();
    let record = forged_deletion(&retired, target);
    deletion(
        &mut retired,
        &mut root,
        DeletionMessage::State {
            records: vec![record],
            next: None,
        },
    );
    assert_eq!(
        root.runtime.poll(ROOM).unwrap().messages[0].body,
        "delete this"
    );
}

fn forged_deletion(
    sender: &Fixture,
    target: crate::message_deletion::MessageOrigin,
) -> crate::message_deletion::DeletionRecord {
    use ed25519_dalek::Signer;
    let key = sender
        .runtime
        .channels
        .get(ROOM)
        .unwrap()
        .node
        .identity_signer()
        .unwrap();
    let actor = hex::encode(key.verifying_key().as_bytes());
    let mut request = crate::message_deletion::protocol::DeleteRequest {
        operation: crate::message_id::occurrence_id("delete"),
        target,
        actor: actor.clone(),
        actor_name: "Retired".into(),
        moderated: false,
        epoch: 0,
        signature: String::new(),
        ownership: crate::message_deletion::ownership::create(
            Some(&sender.store),
            Some(&actor),
            &actor,
        )
        .unwrap(),
    };
    request.signature = hex::encode(key.sign(&request.input().unwrap()).to_bytes());
    shared::canonical(request, DeletionStatus::Pending, None).unwrap()
}
