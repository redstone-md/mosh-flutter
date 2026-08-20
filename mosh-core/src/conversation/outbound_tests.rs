use super::*;
use crate::conversation::test_message::TestMessage;

/// One conversation's outbound state, the pair every runtime holds.
#[derive(Default)]
struct Session {
    messages: MessageLog<TestMessage>,
    attempts: HashMap<String, OutboundAttemptRecord>,
}

impl Session {
    fn outbox(&mut self) -> Outbox<'_, TestMessage> {
        Outbox::new(&mut self.messages, &mut self.attempts)
    }

    /// Stamp a message and file it, the way a runtime's `send` does.
    fn open(&mut self, body: &str) -> Prepared {
        let message = self.messages.stamp(TestMessage::new("me", body));
        let payload = body.as_bytes().to_vec();
        let length = payload.len();
        self.outbox()
            .open(message, "room".to_string(), payload, length)
            .expect("open")
    }
}

#[test]
fn opening_a_send_leaves_the_message_pending_with_its_bytes_kept() {
    let mut session = Session::default();

    let prepared = session.open("hello");

    assert_eq!(prepared.retry_count, 0);
    assert_eq!(prepared.payload, b"hello");
    assert_eq!(
        session.messages[0].delivery_status,
        Some(MessageDeliveryStatus::Pending)
    );
    let attempt = &session.attempts[&prepared.message_id];
    assert_eq!(attempt.conversation_id, "room");
    assert_eq!(attempt.ciphertext_bytes, 5);
    assert_eq!(attempt.retry_count, 0);
    assert_eq!(attempt.delivery_status, MessageDeliveryStatus::Pending);
}

#[test]
fn a_channel_or_group_send_that_lands_forgets_the_attempt() {
    let mut session = Session::default();
    let prepared = session.open("hello");

    let settled = session
        .outbox()
        .settle(&prepared.message_id, Ok(()), OnSent::Forget)
        .expect("settle");

    assert_eq!(settled.status, MessageDeliveryStatus::Sent);
    assert_eq!(settled.error, None);
    assert_eq!(
        session.messages[0].delivery_status,
        Some(MessageDeliveryStatus::Sent)
    );
    assert_eq!(session.messages[0].retryable, Some(false));
    assert!(session.attempts.is_empty());
}

#[test]
fn a_dm_send_that_lands_keeps_the_attempt_for_the_ack() {
    let mut session = Session::default();
    let prepared = session.open("hello");

    session
        .outbox()
        .settle(&prepared.message_id, Ok(()), OnSent::Retain)
        .expect("settle");

    let attempt = &session.attempts[&prepared.message_id];
    assert_eq!(attempt.delivery_status, MessageDeliveryStatus::Sent);
    assert_eq!(attempt.delivery_error, None);
    assert!(attempt.last_send_ms > 0, "the re-send clock must be armed");
}

#[test]
fn a_failed_send_is_retryable_on_both_the_message_and_the_record() {
    let mut session = Session::default();
    let prepared = session.open("hello");

    let settled = session
        .outbox()
        .settle(
            &prepared.message_id,
            Err("no route".to_string()),
            OnSent::Forget,
        )
        .expect("settle");

    assert_eq!(settled.status, MessageDeliveryStatus::Failed);
    assert_eq!(settled.error.as_deref(), Some("no route"));
    assert_eq!(session.messages[0].retryable, Some(true));
    let attempt = &session.attempts[&prepared.message_id];
    assert_eq!(attempt.delivery_status, MessageDeliveryStatus::Failed);
    assert_eq!(attempt.delivery_error.as_deref(), Some("no route"));
}

#[test]
fn a_retry_counts_up_and_re_sends_the_same_bytes() {
    let mut session = Session::default();
    let prepared = session.open("hello");
    session
        .outbox()
        .settle(
            &prepared.message_id,
            Err("no route".to_string()),
            OnSent::Forget,
        )
        .expect("settle");

    let again = session
        .outbox()
        .reopen(&prepared.message_id)
        .expect("reopen");

    assert_eq!(again.message_id, prepared.message_id);
    assert_eq!(again.payload, prepared.payload);
    assert_eq!(again.sent_at_ms, prepared.sent_at_ms);
    assert_eq!(again.retry_count, 1);
    assert_eq!(
        session.messages[0].delivery_status,
        Some(MessageDeliveryStatus::Pending)
    );
    assert_eq!(session.messages[0].delivery_error, None);

    let settled = session
        .outbox()
        .settle(&again.message_id, Ok(()), OnSent::Forget)
        .expect("settle");
    assert_eq!(settled.status, MessageDeliveryStatus::Sent);
    assert_eq!(session.messages[0].retry_count, Some(1));
}

#[test]
fn retrying_a_message_with_no_attempt_left_is_an_error() {
    let mut session = Session::default();

    assert!(session.outbox().reopen("ghost").is_err());
}

#[test]
fn the_stored_json_follows_the_message_so_a_restart_sees_the_failure() {
    let mut session = Session::default();
    let prepared = session.open("hello");

    session
        .outbox()
        .settle(
            &prepared.message_id,
            Err("no route".to_string()),
            OnSent::Retain,
        )
        .expect("settle");

    let attempt = &session.attempts[&prepared.message_id];
    let restored: TestMessage = serde_json::from_str(&attempt.message_json).expect("parse");
    assert_eq!(
        restored.delivery_status,
        Some(MessageDeliveryStatus::Failed)
    );
    assert_eq!(restored.delivery_error.as_deref(), Some("no route"));
    assert_eq!(restored, session.messages[0]);
}

#[test]
fn a_dm_auto_resend_settles_on_the_record_the_first_send_left_behind() {
    let mut session = Session::default();
    let prepared = session.open("hello");
    session
        .outbox()
        .settle(&prepared.message_id, Ok(()), OnSent::Retain)
        .expect("settle");

    // What the re-send pump does: it re-publishes the kept bytes and burns a
    // slot, without touching the message's Sent status.
    let attempt = session
        .attempts
        .get_mut(&prepared.message_id)
        .expect("attempt kept");
    attempt.auto_resends += 1;

    session
        .outbox()
        .settle(&prepared.message_id, Ok(()), OnSent::Retain)
        .expect("settle");

    let attempt = &session.attempts[&prepared.message_id];
    assert_eq!(attempt.auto_resends, 1);
    assert_eq!(attempt.delivery_status, MessageDeliveryStatus::Sent);
    assert_eq!(
        session.messages[0].delivery_status,
        Some(MessageDeliveryStatus::Sent)
    );
}
