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

#[test]
fn history_survives_a_restart() {
    let scratch = Scratch::open("restart");
    let mut history = History::new(DM_HISTORY);
    let mut log = MessageLog::default();
    log.push(TestMessage::new("alice", "first").at(100).with_id("m1"));
    log.push(TestMessage::new("bob", "second").at(200).with_id("m2"));

    assert!(history.write_tail(&scratch.persistence, CONVERSATION, &log, None));

    let (restored, attempts) = scratch.read_back(&mut History::new(DM_HISTORY));
    assert_eq!(restored.len(), 2);
    assert_eq!(restored[0].body, "first");
    assert_eq!(restored[1].body, "second");
    assert!(attempts.is_empty());
}

#[test]
fn an_offered_file_can_be_downloaded_after_both_peers_restart() {
    let sender = Scratch::open("offered-sender");
    let receiver = Scratch::open("offered-receiver");
    let bytes = vec![7; 8192];
    let mut sending = sender.transfer();
    let prepared = sending
        .prepare_outgoing(OutgoingAttachment {
            attachment_id: "attachment-1".to_string(),
            file_name: "clip.bin".to_string(),
            mime: "application/octet-stream".to_string(),
            from_fingerprint: "alice".to_string(),
            bytes: bytes.clone(),
            thumbnail_b64: None,
            voice: None,
        })
        .expect("prepare file");
    let manifest = prepared.manifest.clone();
    let descriptor = sending.record_sent(prepared);
    let mut receiving = receiver.transfer();
    receiving.accept_manifest(manifest).expect("accept offer");

    for (scratch, transfer) in [(&sender, &sending), (&receiver, &receiving)] {
        let mut log = MessageLog::default();
        log.push(ChatMessage {
            from_device: "alice".to_string(),
            body: String::new(),
            message_id: Some("message-1".to_string()),
            sent_at_ms: Some(100),
            attachment: Some(descriptor.clone()),
            call_event: None,
            delivery_status: None,
            delivery_error: None,
            retryable: None,
            retry_count: None,
            read: None,
        });
        History::new(DM_HISTORY).write_tail(
            &scratch.persistence,
            CONVERSATION,
            &log,
            Some(transfer),
        );
    }

    let mut revived_sender = sender.transfer();
    let mut revived_receiver = receiver.transfer();
    for (scratch, transfer, local_author) in [
        (&sender, &mut revived_sender, "alice"),
        (&receiver, &mut revived_receiver, "bob"),
    ] {
        let mut log = MessageLog::<ChatMessage>::default();
        History::new(DM_HISTORY).replay(
            &scratch.persistence,
            CONVERSATION,
            Restore {
                log: &mut log,
                attempts: &mut Attempts::new(),
                transfer,
                local_author,
            },
        );
        assert_eq!(log.len(), 1, "the offer stays in history");
    }

    revived_receiver
        .start_download(&descriptor.attachment_id)
        .expect("download after restart");
    for request in revived_receiver.next_requests() {
        for frame in revived_sender.serve(&request) {
            revived_receiver.ingest(&frame).expect("ingest chunk");
        }
    }
    assert_eq!(
        revived_receiver
            .views()
            .into_iter()
            .find(|view| view.attachment_id == descriptor.attachment_id)
            .expect("restored attachment")
            .state,
        crate::conversation::attachments::AttachmentState::Available
    );
    assert_eq!(
        receiver
            .attachments
            .read_blob(&descriptor.content_hash, &descriptor.file_name)
            .expect("downloaded bytes"),
        bytes
    );
}

#[test]
fn a_message_is_written_once_not_once_per_poll() {
    let scratch = Scratch::open("write-once");
    let mut history = History::new(DM_HISTORY);
    let mut log = MessageLog::default();
    log.push(TestMessage::new("alice", "first").at(100).with_id("m1"));

    assert!(history.write_tail(&scratch.persistence, CONVERSATION, &log, None));
    // An idle poll: nothing new, so nothing is written.
    assert!(!history.write_tail(&scratch.persistence, CONVERSATION, &log, None));

    log.push(TestMessage::new("alice", "second").at(200).with_id("m2"));
    assert!(history.write_tail(&scratch.persistence, CONVERSATION, &log, None));

    let rows = scratch
        .persistence
        .list_history_messages(DM_HISTORY, CONVERSATION)
        .expect("rows");
    assert_eq!(rows.len(), 2);
}

#[test]
fn replaying_picks_up_where_the_last_write_left_off() {
    let scratch = Scratch::open("replay-counts");
    let mut first = History::new(DM_HISTORY);
    let mut log = MessageLog::default();
    log.push(TestMessage::new("alice", "first").at(100).with_id("m1"));
    first.write_tail(&scratch.persistence, CONVERSATION, &log, None);

    let mut second = History::new(DM_HISTORY);
    let (restored, _) = scratch.read_back(&mut second);
    // The replayed message is already down, so the next write must skip it.
    assert!(!second.write_tail(&scratch.persistence, CONVERSATION, &restored, None));
    assert_eq!(
        scratch
            .persistence
            .list_history_messages(DM_HISTORY, CONVERSATION)
            .expect("rows")
            .len(),
        1
    );
}

#[test]
fn forgetting_a_conversation_rewrites_it_from_the_start() {
    let scratch = Scratch::open("forget");
    let mut history = History::new(DM_HISTORY);
    let mut log = MessageLog::default();
    log.push(TestMessage::new("alice", "first").at(100).with_id("m1"));
    history.write_tail(&scratch.persistence, CONVERSATION, &log, None);

    history.forget(CONVERSATION);

    assert!(history.write_tail(&scratch.persistence, CONVERSATION, &log, None));
}

#[test]
fn a_failed_send_comes_back_retryable() {
    let scratch = Scratch::open("failed-send");
    let history = History::new(DM_HISTORY);
    let mut log = MessageLog::default();
    log.push(TestMessage::new("alice", "lost").at(100).with_id("m1"));
    let mut attempts = Attempts::new();
    let mut record = attempt(&log[0], MessageDeliveryStatus::Failed);
    record.delivery_error = Some("no route".to_string());
    attempts.insert("m1".to_string(), record);

    assert!(history.write_send(&scratch.persistence, CONVERSATION, "m1", &log, &attempts));

    let (restored, restored_attempts) = scratch.read_back(&mut History::new(DM_HISTORY));
    assert_eq!(restored.len(), 1);
    assert_eq!(
        restored[0].delivery_status,
        Some(MessageDeliveryStatus::Failed)
    );
    assert_eq!(restored[0].retryable, Some(true));
    // The payload has to still be there, or the retry has nothing to send.
    assert!(restored_attempts.contains_key("m1"));
}

#[test]
fn a_send_cut_short_by_a_restart_comes_back_failed_not_pending() {
    let scratch = Scratch::open("interrupted");
    let history = History::new(DM_HISTORY);
    let mut log = MessageLog::default();
    log.push(TestMessage::new("alice", "in flight").at(100).with_id("m1"));
    let mut attempts = Attempts::new();
    attempts.insert(
        "m1".to_string(),
        attempt(&log[0], MessageDeliveryStatus::Pending),
    );
    history.write_send(&scratch.persistence, CONVERSATION, "m1", &log, &attempts);

    let (restored, _) = scratch.read_back(&mut History::new(DM_HISTORY));

    assert_eq!(
        restored[0].delivery_status,
        Some(MessageDeliveryStatus::Failed)
    );
    assert_eq!(restored[0].retryable, Some(true));
}

// Regression: the message row and the attempt row used to go down as two
// separate transactions, so a crash between them left a Pending message on
// disk with nothing backing it. The attempt loop had no row to reclassify and
// the message came back Pending — a spinner nothing would ever settle. Same
// shape when an attempt row is there but its JSON will not parse.
#[test]
fn a_pending_message_with_no_attempt_row_comes_back_failed() {
    let scratch = Scratch::open("orphan-pending");
    let mut message = TestMessage::new("alice", "torn write")
        .at(100)
        .with_id("m1");
    message.set_delivery(delivery_meta(MessageDeliveryStatus::Pending, None, 0));
    let stored = StoredMessage {
        conversation_id: CONVERSATION.to_string(),
        sent_at_ms: 100,
        message_id: "m1".to_string(),
        message,
        attachment_manifest: None,
    };
    scratch
        .persistence
        .append_history_message(
            DM_HISTORY,
            CONVERSATION,
            100,
            "m1",
            &serde_json::to_vec(&stored).expect("stored json"),
        )
        .expect("message row");

    let (restored, restored_attempts) = scratch.read_back(&mut History::new(DM_HISTORY));

    assert!(restored_attempts.is_empty());
    assert_eq!(
        restored[0].delivery_status,
        Some(MessageDeliveryStatus::Failed)
    );
    // Without an attempt record there are no bytes to replay, so offering a
    // retry would only ever answer "message missing".
    assert_eq!(restored[0].retryable, Some(false));
}

#[test]
fn a_settled_send_drops_its_attempt_record() {
    let scratch = Scratch::open("settled");
    let history = History::new(DM_HISTORY);
    let mut log = MessageLog::default();
    log.push(TestMessage::new("alice", "sent").at(100).with_id("m1"));
    let mut attempts = Attempts::new();
    attempts.insert(
        "m1".to_string(),
        attempt(&log[0], MessageDeliveryStatus::Pending),
    );
    history.write_send(&scratch.persistence, CONVERSATION, "m1", &log, &attempts);

    // What a channel or a group does once the frame is on the wire.
    attempts.remove("m1");
    history.write_send(&scratch.persistence, CONVERSATION, "m1", &log, &attempts);

    let (restored, restored_attempts) = scratch.read_back(&mut History::new(DM_HISTORY));
    assert_eq!(restored.len(), 1);
    assert!(restored_attempts.is_empty());
}

#[test]
fn a_send_of_a_message_that_is_not_in_the_log_writes_nothing() {
    let scratch = Scratch::open("missing-send");
    let history = History::new(DM_HISTORY);
    let log: MessageLog<TestMessage> = MessageLog::default();

    assert!(!history.write_send(
        &scratch.persistence,
        CONVERSATION,
        "ghost",
        &log,
        &Attempts::new()
    ));
    assert!(scratch
        .persistence
        .list_history_messages(DM_HISTORY, CONVERSATION)
        .expect("rows")
        .is_empty());
}

#[test]
fn each_kind_reads_only_its_own_tables() {
    let scratch = Scratch::open("tables");
    let mut dm = History::new(DM_HISTORY);
    let mut log = MessageLog::default();
    log.push(TestMessage::new("alice", "dm only").at(100).with_id("m1"));
    dm.write_tail(&scratch.persistence, CONVERSATION, &log, None);

    let mut channel_log: MessageLog<TestMessage> = MessageLog::default();
    let mut attempts = Attempts::new();
    let mut transfer = scratch.transfer();
    History::new(CHANNEL_HISTORY).replay(
        &scratch.persistence,
        CONVERSATION,
        Restore {
            log: &mut channel_log,
            attempts: &mut attempts,
            transfer: &mut transfer,
            local_author: "alice",
        },
    );

    assert!(channel_log.is_empty());
}

#[test]
fn a_conversation_record_round_trips() {
    let scratch = Scratch::open("record");
    let history = History::new(DM_HISTORY);

    history.write_record(&scratch.persistence, CONVERSATION, &"a record");

    let stored: Vec<String> = history.stored_conversations(&scratch.persistence);
    assert_eq!(stored, vec!["a record".to_string()]);
}

#[test]
fn an_unreadable_record_is_skipped_not_fatal() {
    let scratch = Scratch::open("bad-record");
    let history = History::new(DM_HISTORY);
    scratch
        .persistence
        .put_conversation(DM_HISTORY, "broken", b"not json")
        .expect("write");
    history.write_record(&scratch.persistence, CONVERSATION, &"a record");

    let stored: Vec<String> = history.stored_conversations(&scratch.persistence);
    assert_eq!(stored, vec!["a record".to_string()]);
}
