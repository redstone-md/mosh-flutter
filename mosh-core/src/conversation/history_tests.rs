//! The store proved against a real encrypted database, with the stand-in
//! message: what goes down comes back, and it goes down once.

use std::collections::HashMap;
use std::sync::Arc;

use super::*;
use crate::attachment_runtime::OutgoingAttachment;
use crate::attachment_store::AttachmentStore;
use crate::conversation::test_message::TestMessage;
use crate::persistence::{CHANNEL_HISTORY, DM_HISTORY};
use crate::private_dm_runtime::ChatMessage;

const CONVERSATION: &str = "conv-1";

/// A database and an attachment root of this test's own, both removed when the
/// test ends.
struct Scratch {
    path: std::path::PathBuf,
    persistence: Persistence,
    attachments: Arc<AttachmentStore>,
}

impl Scratch {
    fn open(name: &str) -> Self {
        let dir = std::env::temp_dir().join(format!("mosh-history-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("scratch dir");
        let path = dir.join("history.redb");
        Self {
            persistence: Persistence::open_with_dek(&path, [7u8; 32]).expect("database"),
            attachments: Arc::new(AttachmentStore::new(&dir).expect("attachment store")),
            path,
        }
    }

    fn transfer(&self) -> Transfer {
        Transfer::new(Arc::clone(&self.attachments))
    }

    /// Everything one conversation has on disk, read back into empty state.
    fn read_back(&self, history: &mut History) -> (MessageLog<TestMessage>, Attempts) {
        let mut log = MessageLog::default();
        let mut attempts = Attempts::new();
        let mut transfer = self.transfer();
        history.replay(
            &self.persistence,
            CONVERSATION,
            Restore {
                log: &mut log,
                attempts: &mut attempts,
                transfer: &mut transfer,
                local_author: "alice",
            },
        );
        (log, attempts)
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        if let Some(dir) = self.path.parent() {
            let _ = std::fs::remove_dir_all(dir);
        }
    }
}

type Attempts = HashMap<String, OutboundAttemptRecord>;

fn attempt(message: &TestMessage, status: MessageDeliveryStatus) -> OutboundAttemptRecord {
    OutboundAttemptRecord {
        conversation_id: CONVERSATION.to_string(),
        message_id: message.message_id.clone().expect("stamped message"),
        sent_at_ms: message.sent_at_ms.expect("stamped message"),
        ciphertext_bytes: 0,
        message_json: serde_json::to_string(message).expect("message json"),
        publish_payload_b64: String::new(),
        delivery_status: status,
        delivery_error: None,
        retry_count: 0,
        auto_resends: 0,
        last_send_ms: 0,
    }
}

#[path = "history_tests/messages.rs"]
mod messages;
#[path = "history_tests/replay.rs"]
mod replay;
