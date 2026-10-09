//! The DM state machine on the in-memory transport: two runtimes joined by a
//! [`MemoryNet`], driven only through the public API and judged by the
//! snapshots and the frames that crossed. Prior art: the moss loopback tests
//! beside this module, which these keep the shape of without the mesh. The
//! outbox has its own file, `outbox_tests.rs`, built on the helpers here.

use super::tests::temp_store;
use super::*;
use crate::conversation::read_events::READ_EVENT_CODE;
use crate::conversation::typing::{TYPING_EVENT_CODE, TYPING_EXPIRY_MS, TYPING_REFRESH_MS};
use crate::private_dm_runtime::transport::memory::MemoryNet;

pub(super) const ALICE_ID: &str =
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
pub(super) const BOB_ID: &str = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

pub(super) fn runtime_on(net: &Arc<MemoryNet>, peer_id: &str) -> PrivateDmRuntime {
    PrivateDmRuntime::with_transport(net.endpoint(peer_id), temp_store(), None)
}

/// Alice and Bob, reachable to each other directly, nothing exchanged yet.
pub(super) fn memory_pair() -> (Arc<MemoryNet>, PrivateDmRuntime, PrivateDmRuntime) {
    let net = MemoryNet::new();
    net.link_both(ALICE_ID, BOB_ID, PeerTransport::Direct);
    let alice = runtime_on(&net, ALICE_ID);
    let bob = runtime_on(&net, BOB_ID);
    (net, alice, bob)
}

pub(super) fn invite(alice: &mut PrivateDmRuntime) -> InviteCreated {
    alice
        .create_invite(StartSessionRequest {
            display_name: "Alice".to_string(),
            listen_port: 0,
            static_peer: None,
        })
        .expect("Alice invite should be created")
}

pub(super) fn accept(bob: &mut PrivateDmRuntime, invite: &InviteCreated) {
    bob.accept_invite(AcceptInviteRequest {
        invite_uri: invite.invite_uri.clone(),
        display_name: "Bob".to_string(),
        listen_port: 0,
        static_peer: None,
    })
    .expect("Bob should accept invite");
}

pub(super) fn state_of(runtime: &mut PrivateDmRuntime, session_id: &str) -> DmSessionState {
    runtime
        .poll_session(session_id)
        .expect("poll should pass")
        .state
}

/// Poll both sides in turn until both report Connected, or give up.
pub(super) fn connect(alice: &mut PrivateDmRuntime, bob: &mut PrivateDmRuntime, session_id: &str) {
    for _ in 0..10 {
        let alice_state = state_of(alice, session_id);
        let bob_state = state_of(bob, session_id);
        if alice_state == DmSessionState::Connected && bob_state == DmSessionState::Connected {
            return;
        }
    }
    panic!("the pair never connected");
}

pub(super) fn payload_says(payload: &[u8], word: &str) -> bool {
    String::from_utf8_lossy(payload).contains(word)
}

// ---- Typing indicator (#6) ----

/// Bob's hint deadline, if one stands, from a fresh poll.
fn bob_hint(bob: &mut PrivateDmRuntime, session_id: &str) -> Option<u64> {
    bob.poll_session(session_id)
        .expect("Bob poll should pass")
        .peer_typing_until_ms
}

/// How many TypingIndicator frames an endpoint holds right now.
fn typing_frames(net: &Arc<MemoryNet>, peer_id: &str) -> usize {
    net.endpoint(peer_id)
        .drain()
        .iter()
        .filter(|frame| payload_says(&frame.payload, "TypingIndicator"))
        .count()
}

fn publish_control_from(
    net: &Arc<MemoryNet>,
    invite: &InviteCreated,
    publisher: &str,
    receiver: &str,
    payload: &[u8],
) {
    net.endpoint(publisher)
        .publish(
            &invite.mesh_id,
            &control_channel(&invite.session_id),
            payload,
        )
        .expect("a forged publish is still a publish");
    // Observe the target inbox, then restore every frame for its runtime drain.
    let wire = net.endpoint(receiver).drain();
    assert!(
        wire.iter().any(|frame| frame.payload == payload),
        "the frame must reach the asserted receiver"
    );
    for frame in wire {
        net.endpoint(publisher)
            .publish(&invite.mesh_id, &frame.channel, &frame.payload)
            .expect("the observed frames should return to the receiver");
    }
}

// ---- Read receipts (#7) ----

/// Alice's view of ONE of her messages, from a fresh poll.
fn alice_message(alice: &mut PrivateDmRuntime, session_id: &str, message_id: &str) -> ChatMessage {
    alice
        .poll_session(session_id)
        .expect("Alice poll should pass")
        .messages
        .iter()
        .find(|message| message.message_id.as_deref() == Some(message_id))
        .expect("Alice should hold the message")
        .clone()
}

/// How many ReadReceipt frames an endpoint holds right now.
fn receipt_frames(net: &Arc<MemoryNet>, peer_id: &str) -> usize {
    net.endpoint(peer_id)
        .drain()
        .iter()
        .filter(|frame| payload_says(&frame.payload, "ReadReceipt"))
        .count()
}

/// Delivers every frame an endpoint currently holds by re-publishing them
/// the way MemoryNet would: over the publisher's own links.
fn deliver_inbox(net: &Arc<MemoryNet>, from: &str, to: &str, invite: &InviteCreated) {
    let wire = net.endpoint(to).drain();
    for frame in &wire {
        net.endpoint(from)
            .publish(&invite.mesh_id, &frame.channel, &frame.payload)
            .expect("replay of an observed frame is a publish");
    }
}

/// The events filed under the pinned read code for one session.
fn read_events(session_id: &str) -> Vec<String> {
    crate::moss_ffi::snapshot_event_log()
        .iter()
        .filter(|event| event.event_type == READ_EVENT_CODE)
        .filter(|event| event.detail_json.contains(session_id))
        .map(|event| event.detail_json.clone())
        .collect()
}

/// Propose a shared scratch root, then use the directory production resolved.
/// A prior startup injection wins; receipt tests clear only its toggle file.
fn point_data_dir_once() -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!(
        "mosh-receipts-toggle-{}-shared",
        std::process::id()
    ));
    let _ = crate::api::shared_runtime::set_app_data_dir(dir.to_string_lossy().into_owned());
    crate::api::shared_runtime::resolved_data_dir()
}

fn clear_toggle(dir: &std::path::Path) {
    let _ = std::fs::remove_file(crate::read_receipts::setting_path(dir));
}

// ---- rehydrate snapshot hygiene -------------------------------------------
//
// A conversation record whose MLS snapshot is missing can never rebuild.
// The contract pinned here: a joiner placeholder (empty group_id) is dead
// data and gets deleted at rehydrate; a final record without its snapshot
// stays on disk (its history rows stay recoverable) and is skipped with a
// distinct warning; and a fresh join writes NO row at all until the Welcome
// makes the record final, so the placeholder state is not produced anymore.

/// A per-test redb path, so rehydrate tests never share one store.
fn rehydrate_db(name: &str) -> std::path::PathBuf {
    let mut path = std::env::temp_dir();
    path.push(format!(
        "mosh-dm-rehydrate-{name}-{}.redb",
        std::process::id()
    ));
    let _ = std::fs::remove_file(&path);
    path
}

/// The session records off disk, through the kind's own history reader.
fn stored_session_rows(persistence: &Persistence) -> Vec<contracts::PersistedSession> {
    crate::conversation::history::History::new(DM_HISTORY).stored_conversations(persistence)
}

#[path = "state_tests/connection.rs"]
mod connection;

#[path = "state_tests/receipt_authorization.rs"]
mod receipt_authorization;

#[path = "state_tests/receipt_recovery.rs"]
mod receipt_recovery;

#[path = "state_tests/typing.rs"]
mod typing;

#[path = "state_tests/calls.rs"]
mod calls;

#[path = "state_tests/call_selection.rs"]
mod call_selection;

#[path = "state_tests/restore.rs"]
mod restore;
