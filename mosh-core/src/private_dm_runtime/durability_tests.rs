use super::state_tests::{accept, connect, invite, runtime_on, ALICE_ID, BOB_ID};
use super::transport::memory::MemoryNet;
use super::wire::DATA_CHANNEL_PREFIX;
use super::*;

struct Pair {
    directory: std::path::PathBuf,
    store: Arc<Persistence>,
    attachments: Arc<AttachmentStore>,
    net: Arc<MemoryNet>,
    alice: PrivateDmRuntime,
    bob: PrivateDmRuntime,
    session_id: String,
}

impl Pair {
    fn new(name: &str) -> Self {
        let directory =
            std::env::temp_dir().join(format!("mosh-durable-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&directory);
        std::fs::create_dir_all(&directory).unwrap();
        let store = Arc::new(
            Persistence::open_with_dek(&directory.join("history.redb"), [41; 32]).unwrap(),
        );
        let attachments = Arc::new(AttachmentStore::new(&directory).unwrap());
        let net = MemoryNet::new();
        net.link_both(ALICE_ID, BOB_ID, PeerTransport::Direct);
        let mut alice = PrivateDmRuntime::with_transport(
            net.endpoint(ALICE_ID),
            attachments.clone(),
            Some(store.clone()),
        );
        let mut bob = runtime_on(&net, BOB_ID);
        let invitation = invite(&mut alice);
        accept(&mut bob, &invitation);
        connect(&mut alice, &mut bob, &invitation.session_id);
        Self {
            directory,
            store,
            attachments,
            net,
            alice,
            bob,
            session_id: invitation.session_id,
        }
    }

    fn assert_bob_received_nothing(&mut self) {
        assert!(self
            .bob
            .poll_session(&self.session_id)
            .unwrap()
            .messages
            .is_empty());
    }

    fn restart_alice(&mut self) {
        self.alice = PrivateDmRuntime::with_transport(
            self.net.endpoint(ALICE_ID),
            self.attachments.clone(),
            Some(self.store.clone()),
        );
        self.alice.rehydrate();
    }
}

impl Drop for Pair {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.directory);
    }
}

#[test]
fn refused_admission_never_publishes_during_repair_or_restart() {
    let mut pair = Pair::new("queue");
    let fault = pair.store.refuse_message_writes(DM_HISTORY);
    let error = pair
        .alice
        .send_message(&pair.session_id, "save me first".into())
        .expect_err("storage refusal must reach the caller");
    assert!(matches!(error, PrivateDmRuntimeError::Persistence(_)));
    let failed = pair.alice.poll_session(&pair.session_id).unwrap();
    assert_eq!(
        failed.messages[0].delivery_status,
        Some(MessageDeliveryStatus::Failed)
    );
    for _ in 0..3 {
        pair.alice.service();
        pair.bob.service();
    }
    pair.assert_bob_received_nothing();
    drop(fault);
    pair.alice.service();
    pair.restart_alice();
    pair.alice.service();
    pair.assert_bob_received_nothing();
    let restored = pair.alice.poll_session(&pair.session_id).unwrap();
    assert_eq!(
        restored.messages[0].delivery_status,
        Some(MessageDeliveryStatus::Failed)
    );
    pair.bob
        .send_message(&pair.session_id, "restore handshake evidence".into())
        .unwrap();
    pair.alice.service();
    let message_id = restored.messages[0].message_id.clone().unwrap();
    let sent = pair
        .alice
        .retry_message(&pair.session_id, &message_id)
        .unwrap();
    assert_eq!(sent.delivery_status, MessageDeliveryStatus::Sent);
    let delivered = pair.bob.poll_session(&pair.session_id).unwrap();
    assert_eq!(
        delivered
            .messages
            .iter()
            .filter(|message| message.body == "save me first")
            .count(),
        1
    );
}

#[test]
fn accepted_admission_retains_a_refused_snapshot_and_later_publishes_once() {
    let mut pair = Pair::new("accepted");
    let fault = pair.store.refuse_dm_snapshot_writes();
    let accepted = pair
        .alice
        .send_message(&pair.session_id, "accepted but waiting".into())
        .unwrap();
    assert_eq!(accepted.delivery_status, MessageDeliveryStatus::Queued);
    pair.assert_bob_received_nothing();
    drop(fault);
    pair.alice.service();
    let delivered = pair.bob.poll_session(&pair.session_id).unwrap();
    assert_eq!(delivered.messages.len(), 1);
    assert_eq!(delivered.messages[0].body, "accepted but waiting");
}

#[test]
fn refused_delivery_update_survives_restart_after_storage_recovers() {
    let mut pair = Pair::new("delivery");
    let sent = pair
        .alice
        .send_message(&pair.session_id, "retain delivery".into())
        .unwrap();
    pair.bob.service();
    let fault = pair.store.refuse_message_writes(DM_HISTORY);
    let live = pair.alice.poll_session(&pair.session_id).unwrap();
    assert_eq!(
        live.messages[0].delivery_status,
        Some(MessageDeliveryStatus::Delivered)
    );
    drop(fault);
    pair.alice.service();
    pair.restart_alice();
    let restored = pair.alice.poll_session(&pair.session_id).unwrap();
    assert_eq!(
        restored.messages[0].message_id.as_deref(),
        Some(sent.message_id.as_str())
    );
    assert_eq!(
        restored.messages[0].delivery_status,
        Some(MessageDeliveryStatus::Delivered)
    );
}

#[test]
fn refused_settlement_save_reports_the_text_that_actually_left() {
    let mut pair = Pair::new("settlement");
    let fault = Arc::new(std::sync::Mutex::new(None));
    let held = fault.clone();
    let store = pair.store.clone();
    pair.net.drop_frames(ALICE_ID, BOB_ID, move |channel, _| {
        if channel.starts_with(DATA_CHANNEL_PREFIX) {
            let mut held = held.lock().unwrap();
            if held.is_none() {
                *held = Some(store.refuse_message_writes(DM_HISTORY));
            }
        }
        false
    });
    let sent = pair
        .alice
        .send_message(&pair.session_id, "publication already happened".into())
        .expect("a settled-save refusal must not claim the text was refused");
    assert_eq!(sent.delivery_status, MessageDeliveryStatus::Sent);
    assert_eq!(
        pair.bob.poll_session(&pair.session_id).unwrap().messages[0].body,
        "publication already happened"
    );
    pair.net.drop_frames(ALICE_ID, BOB_ID, |_, _| false);
    drop(fault.lock().unwrap().take());
    pair.alice.service();
    pair.restart_alice();
    let restored = pair.alice.poll_session(&pair.session_id).unwrap();
    assert_eq!(
        restored.messages[0].delivery_status,
        Some(MessageDeliveryStatus::Delivered)
    );
}

#[test]
fn refused_mls_tail_snapshot_is_retried_before_the_next_restart() {
    let mut pair = Pair::new("snapshot");
    let fault = pair.store.refuse_dm_snapshot_writes();
    pair.bob
        .send_message(&pair.session_id, "incoming during refusal".into())
        .unwrap();
    assert_eq!(
        pair.alice.poll_session(&pair.session_id).unwrap().messages[0].body,
        "incoming during refusal"
    );
    pair.bob.service();
    drop(fault);
    pair.alice.service();
    pair.restart_alice();
    pair.alice
        .send_message(&pair.session_id, "outgoing after restart".into())
        .unwrap();
    let received = pair.bob.poll_session(&pair.session_id).unwrap();
    assert!(received
        .messages
        .iter()
        .any(|message| message.body == "outgoing after restart"));
}

#[test]
fn publishing_a_saved_queue_retains_the_advanced_mls_snapshot() {
    let mut pair = Pair::new("queued-snapshot");
    pair.bob
        .send_message(&pair.session_id, "handshake evidence".into())
        .unwrap();
    pair.alice.service();
    pair.bob.service();
    pair.net.refuse_publishes(ALICE_ID, true);
    let queued = pair
        .alice
        .send_message(&pair.session_id, "already saved queue".into())
        .unwrap();
    assert_eq!(queued.delivery_status, MessageDeliveryStatus::Queued);
    pair.net.refuse_publishes(ALICE_ID, false);
    pair.alice.service();
    let received = pair.bob.poll_session(&pair.session_id).unwrap();
    assert!(received
        .messages
        .iter()
        .any(|message| message.body == "already saved queue"));
    pair.restart_alice();
    pair.alice
        .send_message(&pair.session_id, "fresh after queue restart".into())
        .unwrap();
    let received = pair.bob.poll_session(&pair.session_id).unwrap();
    assert!(received
        .messages
        .iter()
        .any(|message| message.body == "fresh after queue restart"));
}

#[path = "durability_tests/attachments.rs"]
mod attachments;
