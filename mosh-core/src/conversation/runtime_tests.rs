//! The shell proved against a real encrypted database with a stand-in kind:
//! when a record is worth saving, when the kind's own state goes down with it,
//! and what a conversation the user left leaves behind.

use std::cell::Cell;
use std::sync::Arc;

use super::*;
use crate::conversation::test_message::TestMessage;
use crate::persistence::DM_HISTORY;

const CONVERSATION: &str = "conv-1";

/// A stand-in kind. Nothing about a wire, only the four answers the shell
/// asks for, plus a tally of the writes it caused.
struct FakeSession {
    id: String,
    log: MessageLog<TestMessage>,
    attempts: HashMap<String, OutboundAttemptRecord>,
    /// What `record_is_final` answers — a joiner flips this once it has
    /// everything its record needs.
    ready: bool,
    /// What `record_changed` answers, cleared when the record is written.
    changed: bool,
    extra_writes: Cell<usize>,
}

impl FakeSession {
    fn new(id: &str) -> Self {
        Self {
            id: id.to_string(),
            log: MessageLog::default(),
            attempts: HashMap::new(),
            ready: true,
            changed: false,
            extra_writes: Cell::new(0),
        }
    }

    fn say(&mut self, body: &str) -> TestMessage {
        let message = self.log.stamp(TestMessage::new("alice", body));
        self.log.push(message.clone());
        message
    }
}

impl ConversationSession for FakeSession {
    type Message = TestMessage;
    type Record = String;

    fn conversation_id(&self) -> &str {
        &self.id
    }

    fn log(&self) -> &MessageLog<TestMessage> {
        &self.log
    }

    fn attempts(&self) -> &HashMap<String, OutboundAttemptRecord> {
        &self.attempts
    }

    fn record(&self) -> String {
        format!("record for {}", self.id)
    }

    fn write_extra(&self, _persistence: &Persistence) {
        self.extra_writes.set(self.extra_writes.get() + 1);
    }

    fn record_is_final(&self) -> bool {
        self.ready
    }

    fn record_changed(&self) -> bool {
        self.changed
    }

    fn record_written(&mut self) {
        self.changed = false;
    }
}

/// A database and an attachment root of this test's own, both removed when the
/// test ends.
struct Scratch {
    path: std::path::PathBuf,
    persistence: Arc<Persistence>,
    attachments: Arc<AttachmentStore>,
}

impl Scratch {
    fn open(name: &str) -> Self {
        let dir = std::env::temp_dir().join(format!("mosh-shell-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("scratch dir");
        let path = dir.join("history.redb");
        Self {
            persistence: Arc::new(Persistence::open_with_dek(&path, [9u8; 32]).expect("database")),
            attachments: Arc::new(AttachmentStore::new(&dir).expect("attachment store")),
            path,
        }
    }

    fn runtime(&self) -> ConversationRuntime<FakeSession> {
        ConversationRuntime::new(
            Arc::clone(&self.attachments),
            Some(Arc::clone(&self.persistence)),
            DM_HISTORY,
        )
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        if let Some(dir) = self.path.parent() {
            let _ = std::fs::remove_dir_all(dir);
        }
    }
}

fn extra_writes(runtime: &ConversationRuntime<FakeSession>) -> usize {
    runtime
        .get(CONVERSATION)
        .expect("the conversation")
        .extra_writes
        .get()
}

#[test]
fn a_record_is_saved_once_it_is_final_and_not_before() {
    let scratch = Scratch::open("final");
    let mut runtime = scratch.runtime();
    let mut session = FakeSession::new(CONVERSATION);
    session.ready = false;
    session.say("first");
    runtime.insert(CONVERSATION.to_string(), session);

    runtime.persist_tail();
    assert!(
        runtime.stored_records::<String>().is_empty(),
        "a record that cannot be rebuilt must not be saved"
    );

    runtime
        .get_mut(CONVERSATION)
        .expect("the conversation")
        .ready = true;
    runtime.persist_tail();

    assert_eq!(
        runtime.stored_records::<String>(),
        vec![format!("record for {CONVERSATION}")]
    );
}

#[test]
fn an_unchanged_record_is_not_written_again() {
    let scratch = Scratch::open("once");
    let mut runtime = scratch.runtime();
    runtime.insert(CONVERSATION.to_string(), FakeSession::new(CONVERSATION));

    runtime.persist_tail();
    let after_first = extra_writes(&runtime);
    runtime.persist_tail();
    runtime.persist_tail();

    assert_eq!(
        extra_writes(&runtime),
        after_first,
        "an idle poll must not re-encrypt the kind's whole state"
    );
}

#[test]
fn a_changed_record_is_written_again_and_then_settles() {
    let scratch = Scratch::open("changed");
    let mut runtime = scratch.runtime();
    runtime.insert(CONVERSATION.to_string(), FakeSession::new(CONVERSATION));
    runtime.persist_tail();
    let after_first = extra_writes(&runtime);

    runtime
        .get_mut(CONVERSATION)
        .expect("the conversation")
        .changed = true;
    runtime.persist_tail();
    let after_change = extra_writes(&runtime);
    runtime.persist_tail();

    assert_eq!(after_change, after_first + 1, "a changed record is saved");
    assert_eq!(
        extra_writes(&runtime),
        after_change,
        "writing the record clears the change, so the next poll is idle"
    );
}

#[test]
fn new_messages_save_the_kind_state_with_them() {
    let scratch = Scratch::open("messages");
    let mut runtime = scratch.runtime();
    runtime.insert(CONVERSATION.to_string(), FakeSession::new(CONVERSATION));
    runtime.persist_tail();
    let idle = extra_writes(&runtime);

    runtime
        .get_mut(CONVERSATION)
        .expect("the conversation")
        .say("something new");
    runtime.persist_tail();

    assert_eq!(extra_writes(&runtime), idle + 1);
}

#[test]
fn a_send_saves_its_message_and_only_a_first_send_saves_the_kind_state() {
    let scratch = Scratch::open("send");
    let mut runtime = scratch.runtime();
    let mut session = FakeSession::new(CONVERSATION);
    let message = session.say("hello");
    let message_id = message.message_id.clone().expect("a stamped message");
    runtime.insert(CONVERSATION.to_string(), session);
    let before = extra_writes(&runtime);

    runtime.persist_send(CONVERSATION, &message_id, true);
    let after_first = extra_writes(&runtime);
    runtime.persist_send(CONVERSATION, &message_id, false);

    assert_eq!(after_first, before + 1, "a first send saves the kind state");
    assert_eq!(
        extra_writes(&runtime),
        after_first,
        "the settle that follows it does not"
    );

    // The message really went down: a second shell reads it back.
    let mut restored = scratch.runtime();
    let mut log: MessageLog<TestMessage> = MessageLog::default();
    let mut attempts = HashMap::new();
    let mut transfer =
        crate::conversation::transfer::Transfer::new(Arc::clone(&scratch.attachments));
    restored.replay(
        CONVERSATION,
        Restore {
            log: &mut log,
            attempts: &mut attempts,
            transfer: &mut transfer,
            local_author: "alice",
        },
    );
    assert_eq!(log.len(), 1);
}

#[test]
fn a_send_for_a_message_nobody_holds_writes_nothing() {
    let scratch = Scratch::open("stray-send");
    let mut runtime = scratch.runtime();
    runtime.insert(CONVERSATION.to_string(), FakeSession::new(CONVERSATION));
    let before = extra_writes(&runtime);

    runtime.persist_send(CONVERSATION, "never-sent", true);
    runtime.persist_send("never-joined", "never-sent", true);

    assert_eq!(extra_writes(&runtime), before);
    assert!(runtime.stored_records::<String>().is_empty());
}

#[test]
fn a_fresh_conversation_saves_its_record_before_anyone_speaks() {
    let scratch = Scratch::open("fresh");
    let mut runtime = scratch.runtime();
    runtime.insert(CONVERSATION.to_string(), FakeSession::new(CONVERSATION));

    runtime.persist_record(CONVERSATION, true);
    let after_create = extra_writes(&runtime);
    runtime.persist_tail();

    assert_eq!(
        runtime.stored_records::<String>(),
        vec![format!("record for {CONVERSATION}")]
    );
    assert_eq!(
        extra_writes(&runtime),
        after_create,
        "a record saved as final is not saved again by the next poll"
    );
}

#[test]
fn a_placeholder_record_is_saved_without_claiming_to_be_final() {
    let scratch = Scratch::open("placeholder");
    let mut runtime = scratch.runtime();
    runtime.insert(CONVERSATION.to_string(), FakeSession::new(CONVERSATION));

    runtime.persist_record(CONVERSATION, false);
    let after_create = extra_writes(&runtime);
    runtime.persist_tail();

    assert_eq!(
        extra_writes(&runtime),
        after_create + 1,
        "a placeholder must be replaced once the conversation is whole"
    );
}

#[test]
fn a_record_read_back_off_disk_is_not_written_again() {
    let scratch = Scratch::open("rehydrated");
    let mut runtime = scratch.runtime();
    runtime.insert(CONVERSATION.to_string(), FakeSession::new(CONVERSATION));

    // What rehydrate does: the record came off disk, so it is already final.
    runtime.mark_record_final(CONVERSATION);
    let before = extra_writes(&runtime);
    runtime.persist_tail();

    assert_eq!(
        extra_writes(&runtime),
        before,
        "a record read back off disk must not be replaced with itself"
    );
}

#[test]
fn a_conversation_the_user_left_is_written_again_from_the_start() {
    let scratch = Scratch::open("forget");
    let mut runtime = scratch.runtime();
    let mut session = FakeSession::new(CONVERSATION);
    session.say("first");
    runtime.insert(CONVERSATION.to_string(), session);
    runtime.persist_tail();
    let after_first = extra_writes(&runtime);

    runtime.forget(CONVERSATION);
    runtime.persist_tail();

    assert_eq!(
        extra_writes(&runtime),
        after_first + 1,
        "forgetting puts the conversation back to never-written"
    );
}
