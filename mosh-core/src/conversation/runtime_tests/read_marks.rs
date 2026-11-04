//! Read marks through the shell: what a restart keeps, what never counts.
use super::*;
use crate::conversation::now_ms;
use crate::conversation::read_marks::UnreadState;

fn hear(runtime: &mut ConversationRuntime<TestSession>, from: &str, id: &str, at: u64) {
    let session = runtime.get_mut(CONVERSATION).expect("the conversation");
    let message = session
        .log
        .stamp(TestMessage::new(from, "hi").at(at).with_id(id));
    session.log.push(message);
}

fn unread(runtime: &mut ConversationRuntime<TestSession>) -> UnreadState {
    runtime.unread(CONVERSATION).expect("an open conversation")
}

#[test]
fn unread_messages_survive_a_restart_until_viewed() {
    let scratch = Scratch::open("read-restart");
    let mut runtime = scratch.runtime();
    runtime.insert(CONVERSATION.into(), TestSession::new(CONVERSATION));
    assert_eq!(unread(&mut runtime).count, 0);
    let later = now_ms() + 1_000;
    hear(&mut runtime, "bob", "m1", later);
    hear(&mut runtime, "bob", "m2", later + 1);

    let mut restarted = scratch.runtime();
    restarted.insert(CONVERSATION.into(), TestSession::new(CONVERSATION));
    hear(&mut restarted, "bob", "m1", later);
    hear(&mut restarted, "bob", "m2", later + 1);
    assert_eq!(
        unread(&mut restarted),
        UnreadState {
            count: 2,
            first_unread_message_id: Some("m1".into())
        }
    );

    restarted.mark_read(CONVERSATION);
    let mut again = scratch.runtime();
    again.insert(CONVERSATION.into(), TestSession::new(CONVERSATION));
    hear(&mut again, "bob", "m1", later);
    hear(&mut again, "bob", "m2", later + 1);
    assert_eq!(
        unread(&mut again).count,
        0,
        "a viewed message must not return"
    );
}

#[test]
fn history_from_before_the_conversation_appeared_and_own_messages_never_count() {
    let scratch = Scratch::open("read-floor");
    let mut runtime = scratch.runtime();
    runtime.insert(CONVERSATION.into(), TestSession::new(CONVERSATION));
    let floor = now_ms();
    assert_eq!(unread(&mut runtime).count, 0);

    hear(&mut runtime, "bob", "archived", floor - 60_000);
    hear(&mut runtime, "alice", "mine", floor + 1_000);
    hear(&mut runtime, "bob", "new", floor + 2_000);

    assert_eq!(
        unread(&mut runtime),
        UnreadState {
            count: 1,
            first_unread_message_id: Some("new".into())
        }
    );
}

#[test]
fn a_rejoined_conversation_does_not_inherit_what_was_seen_before() {
    let scratch = Scratch::open("read-left");
    let mut runtime = scratch.runtime();
    runtime.insert(CONVERSATION.into(), TestSession::new(CONVERSATION));
    let later = now_ms() + 1_000;
    hear(&mut runtime, "bob", "m1", later);
    runtime.mark_read(CONVERSATION);

    runtime.remove(CONVERSATION);
    runtime.forget(CONVERSATION);
    scratch.persistence.delete_session(CONVERSATION).unwrap();

    let mut rejoined = scratch.runtime();
    rejoined.insert(CONVERSATION.into(), TestSession::new(CONVERSATION));
    assert_eq!(unread(&mut rejoined).count, 0);
    hear(&mut rejoined, "bob", "m2", later);
    assert_eq!(unread(&mut rejoined).count, 1);
}

#[test]
fn hiding_a_seen_message_does_not_hide_the_next_one() {
    let scratch = Scratch::open("read-hidden");
    let mut runtime = scratch.runtime();
    runtime.insert(CONVERSATION.into(), TestSession::new(CONVERSATION));
    let later = now_ms() + 1_000;
    hear(&mut runtime, "bob", "m1", later);
    runtime.mark_read(CONVERSATION);

    let session = runtime.get_mut(CONVERSATION).expect("the conversation");
    let seen = session.log.find_mut("m1").expect("m1");
    seen.metadata = Some(crate::message_deletion::MessageMetadata {
        deletion: Some(crate::message_deletion::DeletionMarker {
            scope: crate::message_deletion::DeleteScope::ForMe,
            status: crate::message_deletion::DeletionStatus::Confirmed,
            administrator: None,
        }),
        ..Default::default()
    });
    hear(&mut runtime, "bob", "m2", later + 1);

    assert_eq!(unread(&mut runtime).count, 1);
}

#[test]
fn a_conversation_with_history_counts_what_is_recovered_after_it() {
    let scratch = Scratch::open("read-upgrade");
    let mut runtime = scratch.runtime();
    let last_stored = now_ms() - 60_000;
    let mut restored = TestSession::new(CONVERSATION);
    let old = restored
        .log
        .stamp(TestMessage::new("bob", "hi").at(last_stored).with_id("old"));
    restored.log.push(old);
    runtime.insert(CONVERSATION.into(), restored);
    // Recovered by the same poll that reports the conversation first.
    hear(&mut runtime, "bob", "recovered", last_stored + 30_000);

    assert_eq!(
        unread(&mut runtime),
        UnreadState {
            count: 1,
            first_unread_message_id: Some("recovered".into())
        }
    );
}

#[test]
fn an_own_message_counts_as_own_whatever_its_record_claims() {
    let scratch = Scratch::open("read-own");
    let mut runtime = scratch.runtime();
    runtime.insert(CONVERSATION.into(), TestSession::new(CONVERSATION));
    assert_eq!(unread(&mut runtime).count, 0);
    let later = now_ms() + 1_000;
    hear(&mut runtime, "alice", "recovered-own", later);
    let session = runtime.get_mut(CONVERSATION).expect("the conversation");
    session.log.find_mut("recovered-own").expect("own").metadata =
        Some(crate::message_deletion::MessageMetadata {
            is_own: Some(false),
            ..Default::default()
        });

    assert_eq!(unread(&mut runtime).count, 0);
}

#[test]
fn the_first_unread_is_the_same_before_and_after_a_restart() {
    let scratch = Scratch::open("read-order");
    let mut runtime = scratch.runtime();
    runtime.insert(CONVERSATION.into(), TestSession::new(CONVERSATION));
    assert_eq!(unread(&mut runtime).count, 0);
    let later = now_ms() + 1_000;
    hear(&mut runtime, "bob", "newer", later + 10);
    hear(&mut runtime, "bob", "older", later + 5);
    let before = unread(&mut runtime);

    let mut restarted = scratch.runtime();
    restarted.insert(CONVERSATION.into(), TestSession::new(CONVERSATION));
    hear(&mut restarted, "bob", "older", later + 5);
    hear(&mut restarted, "bob", "newer", later + 10);

    assert_eq!(unread(&mut restarted), before);
    assert_eq!(before.first_unread_message_id, Some("older".into()));
}
