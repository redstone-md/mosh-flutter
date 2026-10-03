use super::*;
use crate::conversation::outbound::{OnSent, Outbox};

#[test]
fn refused_record_remains_due_until_the_record_can_be_reloaded() {
    let scratch = Scratch::open("refused-record");
    let mut runtime = scratch.runtime();
    runtime.insert(CONVERSATION.into(), TestSession::new(CONVERSATION));
    let fault = scratch.persistence.refuse_record_writes(DM_HISTORY);
    assert!(runtime.persist_tail().is_err());
    drop(fault);
    runtime.persist_tail().expect("retry the record");
    assert_eq!(
        scratch.runtime().stored_records::<String>(),
        vec!["record for conv-1"]
    );
}

#[test]
fn refused_placeholder_record_is_retried_before_it_becomes_final() {
    let scratch = Scratch::open("refused-placeholder");
    let mut runtime = scratch.runtime();
    let mut session = TestSession::new(CONVERSATION);
    session.ready = false;
    runtime.insert(CONVERSATION.into(), session);
    let fault = scratch.persistence.refuse_record_writes(DM_HISTORY);
    assert!(runtime.persist_record(CONVERSATION, false).is_err());
    drop(fault);
    runtime.persist_tail().expect("retry the placeholder");
    assert_eq!(
        scratch.runtime().stored_records::<String>(),
        vec!["record for conv-1"]
    );
}

#[test]
fn refused_tail_rows_are_retried_and_survive_replay() {
    let scratch = Scratch::open("refused-tail");
    let mut runtime = scratch.runtime();
    let mut session = TestSession::new(CONVERSATION);
    session.say("saved after repair");
    runtime.insert(CONVERSATION.into(), session);
    let fault = scratch.persistence.refuse_message_writes(DM_HISTORY);
    assert!(runtime.persist_tail().is_err());
    drop(fault);
    runtime.persist_tail().expect("retry the tail");
    let mut restored = TestSession::new(CONVERSATION);
    runtime.replay(
        CONVERSATION,
        Restore {
            log: &mut restored.log,
            attempts: &mut restored.attempts,
            transfer: &mut crate::conversation::transfer::Transfer::new(
                scratch.attachments.clone(),
            ),
            local_author: "alice",
        },
    );
    assert_eq!(restored.log.len(), 1);
    assert_eq!(restored.log[0].body, "saved after repair");
}

#[test]
fn refused_settlement_save_is_retried_after_the_attempt_is_forgotten() {
    let scratch = Scratch::open("refused-settlement");
    let mut runtime = scratch.runtime();
    let mut session = TestSession::new(CONVERSATION);
    let message = session
        .log
        .stamp(TestMessage::new("alice", "already published"));
    let prepared = Outbox::new(&mut session.log, &mut session.attempts)
        .open(message, CONVERSATION.into(), b"payload".to_vec(), 7)
        .unwrap();
    runtime.insert(CONVERSATION.into(), session);
    runtime
        .persist_send(CONVERSATION, &prepared.message_id, true)
        .unwrap();
    let session = runtime.get_mut(CONVERSATION).unwrap();
    Outbox::new(&mut session.log, &mut session.attempts)
        .settle(&prepared.message_id, Ok(()), OnSent::Forget)
        .unwrap();
    let fault = scratch.persistence.refuse_message_writes(DM_HISTORY);
    assert!(runtime
        .persist_send(CONVERSATION, &prepared.message_id, false)
        .is_err());
    drop(fault);
    runtime.persist_tail().expect("retry the settlement");
    let mut restored = TestSession::new(CONVERSATION);
    runtime.replay(
        CONVERSATION,
        Restore {
            log: &mut restored.log,
            attempts: &mut restored.attempts,
            transfer: &mut crate::conversation::transfer::Transfer::new(
                scratch.attachments.clone(),
            ),
            local_author: "alice",
        },
    );
    assert_eq!(
        restored.log[0].delivery_status,
        Some(crate::outbound_delivery::MessageDeliveryStatus::Sent)
    );
    assert!(restored.attempts.is_empty());
}

#[test]
fn refused_atomic_send_does_not_leak_a_tail_row_or_block_other_conversations() {
    let scratch = Scratch::open("refused-attempt");
    let mut runtime = scratch.runtime();
    let mut session = TestSession::new(CONVERSATION);
    let message = session
        .log
        .stamp(TestMessage::new("alice", "needs its attempt"));
    let prepared = Outbox::new(&mut session.log, &mut session.attempts)
        .queue(message, CONVERSATION.into())
        .unwrap();
    runtime.insert(CONVERSATION.into(), session);
    let mut other = TestSession::new("conv-2");
    other.say("independent history");
    runtime.insert("conv-2".into(), other);
    let fault = scratch.persistence.refuse_attempt_writes();
    assert!(runtime
        .persist_send(CONVERSATION, &prepared.message_id, true)
        .is_err());
    assert!(runtime.persist_tail().is_err());
    assert!(scratch
        .persistence
        .list_history_messages(DM_HISTORY, CONVERSATION)
        .unwrap()
        .is_empty());
    assert_eq!(
        scratch
            .persistence
            .list_history_messages(DM_HISTORY, "conv-2")
            .unwrap()
            .len(),
        1
    );
    drop(fault);
    runtime.persist_tail().unwrap();
    assert_eq!(
        scratch
            .persistence
            .list_outbound_attempts(DM_HISTORY.outbound_scope, CONVERSATION)
            .unwrap()
            .len(),
        1
    );
}
