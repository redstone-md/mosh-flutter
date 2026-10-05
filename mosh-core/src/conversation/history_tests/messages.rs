use super::*;

#[test]
fn history_survives_a_restart() {
    let scratch = Scratch::open("restart");
    let mut history = History::new(DM_HISTORY);
    let mut log = MessageLog::default();
    log.push(TestMessage::new("alice", "first").at(100).with_id("m1"));
    log.push(TestMessage::new("bob", "second").at(200).with_id("m2"));

    assert!(history
        .write_tail(&scratch.persistence, CONVERSATION, &log, None)
        .unwrap());

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
            metadata: None,
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
        History::new(DM_HISTORY)
            .write_tail(&scratch.persistence, CONVERSATION, &log, Some(transfer))
            .unwrap();
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

    assert!(history
        .write_tail(&scratch.persistence, CONVERSATION, &log, None)
        .unwrap());
    // An idle poll: nothing new, so nothing is written.
    assert!(!history
        .write_tail(&scratch.persistence, CONVERSATION, &log, None)
        .unwrap());

    log.push(TestMessage::new("alice", "second").at(200).with_id("m2"));
    assert!(history
        .write_tail(&scratch.persistence, CONVERSATION, &log, None)
        .unwrap());

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
    first
        .write_tail(&scratch.persistence, CONVERSATION, &log, None)
        .unwrap();

    let mut second = History::new(DM_HISTORY);
    let (restored, _) = scratch.read_back(&mut second);
    // The replayed message is already down, so the next write must skip it.
    assert!(!second
        .write_tail(&scratch.persistence, CONVERSATION, &restored, None)
        .unwrap());
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
    history
        .write_tail(&scratch.persistence, CONVERSATION, &log, None)
        .unwrap();

    history.forget(CONVERSATION);

    assert!(history
        .write_tail(&scratch.persistence, CONVERSATION, &log, None)
        .unwrap());
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

    assert!(history
        .write_send(&scratch.persistence, CONVERSATION, "m1", &log, &attempts)
        .unwrap());

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
