use super::*;

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
    history
        .write_send(&scratch.persistence, CONVERSATION, "m1", &log, &attempts)
        .unwrap();

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
    history
        .write_send(&scratch.persistence, CONVERSATION, "m1", &log, &attempts)
        .unwrap();

    // What a channel or a group does once the frame is on the wire.
    attempts.remove("m1");
    history
        .write_send(&scratch.persistence, CONVERSATION, "m1", &log, &attempts)
        .unwrap();

    let (restored, restored_attempts) = scratch.read_back(&mut History::new(DM_HISTORY));
    assert_eq!(restored.len(), 1);
    assert!(restored_attempts.is_empty());
}

#[test]
fn a_send_of_a_message_that_is_not_in_the_log_writes_nothing() {
    let scratch = Scratch::open("missing-send");
    let history = History::new(DM_HISTORY);
    let log: MessageLog<TestMessage> = MessageLog::default();

    assert!(!history
        .write_send(
            &scratch.persistence,
            CONVERSATION,
            "ghost",
            &log,
            &Attempts::new()
        )
        .unwrap());
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
    dm.write_tail(&scratch.persistence, CONVERSATION, &log, None)
        .unwrap();

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

    history
        .write_record(&scratch.persistence, CONVERSATION, &"a record")
        .unwrap();

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
    history
        .write_record(&scratch.persistence, CONVERSATION, &"a record")
        .unwrap();

    let stored: Vec<String> = history.stored_conversations(&scratch.persistence);
    assert_eq!(stored, vec!["a record".to_string()]);
}
