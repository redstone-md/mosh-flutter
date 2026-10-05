//! The channel runtime tests.
use super::*;
use crate::conversation::history::StoredMessage;
use crate::moss_ffi::{
    drain_received_messages, fail_next_test_publish, no_peers_next_test_publish, MossFfiRuntime,
    MOSS_TEST_LOCK,
};
use crate::persistence::Persistence;
use std::path::PathBuf;

fn temp_store() -> Arc<AttachmentStore> {
    let mut path = std::env::temp_dir();
    path.push(format!(
        "mosh-channel-attachments-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    Arc::new(AttachmentStore::new(&path).expect("attachment store should init"))
}

#[path = "runtime_tests/lifecycle.rs"]
mod lifecycle;

#[path = "runtime_tests/delivery.rs"]
mod delivery;

#[path = "runtime_tests/deletion.rs"]
mod deletion;

#[test]
fn identical_files_are_distinct_message_occurrences() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    drain_received_messages();
    let native = Arc::new(MossFfiRuntime::load_default().unwrap());
    let mut runtime = ChannelRuntime::from_shared(native, temp_store(), None);
    runtime
        .join(JoinChannelRequest {
            name: "repeated-file".into(),
            display_name: "Alice".into(),
            listen_port: 42417,
            static_peer: None,
        })
        .unwrap();
    let first = runtime
        .send_attachment(
            "repeated-file",
            "note.txt".into(),
            "text/plain".into(),
            b"same bytes".to_vec(),
            None,
            None,
        )
        .unwrap();
    let second = runtime
        .send_attachment(
            "repeated-file",
            "note.txt".into(),
            "text/plain".into(),
            b"same bytes".to_vec(),
            None,
            None,
        )
        .unwrap();
    assert_ne!(first.attachment_id, second.attachment_id);
    assert_eq!(first.content_hash, second.content_hash);
    assert_eq!(runtime.poll("repeated-file").unwrap().messages.len(), 2);
    runtime.leave("repeated-file").unwrap();
}

#[test]
fn a_sent_channel_text_retains_a_verifiable_author() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    drain_received_messages();
    let native = Arc::new(MossFfiRuntime::load_default().unwrap());
    let mut runtime = ChannelRuntime::from_shared(native, temp_store(), None);
    runtime
        .join(JoinChannelRequest {
            name: "verified-text".into(),
            display_name: "Alice".into(),
            listen_port: 42418,
            static_peer: None,
        })
        .unwrap();
    runtime.send("verified-text", "hello".into()).unwrap();
    let snapshot = runtime.poll("verified-text").unwrap();
    let message = &snapshot.messages[0];
    let origin = message.metadata.as_ref().unwrap().origin.as_ref().unwrap();
    origin
        .verify(
            "channel:verified-text",
            message.message_id.as_deref().unwrap(),
            b"hello",
        )
        .unwrap();
    assert_eq!(origin.author, snapshot.device_fingerprint);
    assert!(origin
        .verify(
            "channel:another-room",
            message.message_id.as_deref().unwrap(),
            b"hello"
        )
        .is_err());
    runtime.leave("verified-text").unwrap();
}
