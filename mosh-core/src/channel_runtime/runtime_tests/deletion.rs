use super::*;
use crate::message_deletion::{
    cipher, fragments, protocol::DeletionMessage, shared, DeleteScope, DeletionStatus,
};
use crate::test_temp_directory::TempDirectory;

const ROOM: &str = "deletion-test";
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
