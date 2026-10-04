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
