//! The DM runtime integration tests over the real Moss loopback.
use super::*;

use crate::attachment_runtime::CHUNK_SIZE;
use crate::moss_ffi::{drain_received_messages, MossFfiRuntime, MOSS_TEST_LOCK};

pub(super) fn temp_store() -> Arc<AttachmentStore> {
    let mut path = std::env::temp_dir();
    path.push(format!(
        "mosh-dm-attachments-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    Arc::new(AttachmentStore::new(&path).expect("attachment store should init"))
}

// Builds a lone Alice session on `port` — enough to drive the session-level
// pumps and control handlers without a live counterpart.
fn lone_session(port: u16) -> (PrivateDmRuntime, String) {
    drain_received_messages();
    let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
    let mut alice = PrivateDmRuntime::from_shared(runtime, temp_store(), None);
    let invite = alice
        .create_invite(StartSessionRequest {
            display_name: "Alice".to_string(),
            listen_port: port,
            static_peer: None,
        })
        .expect("Alice invite should be created");
    (alice, invite.session_id)
}

fn wait_for_attachment(
    runtime: &mut PrivateDmRuntime,
    session_id: &str,
    attachment_id: &str,
) -> String {
    for _ in 0..40 {
        let snapshot = runtime.poll_session(session_id).expect("poll should pass");
        if snapshot
            .attachments
            .iter()
            .any(|view| view.attachment_id == attachment_id)
        {
            return attachment_id.to_string();
        }
        std::thread::sleep(std::time::Duration::from_millis(100));
    }
    panic!("attachment manifest did not arrive");
}

fn wait_for_attachment_available(
    alice: &mut PrivateDmRuntime,
    bob: &mut PrivateDmRuntime,
    session_id: &str,
    attachment_id: &str,
) {
    for _ in 0..120 {
        let _ = alice.poll_session(session_id);
        let snapshot = bob.poll_session(session_id).expect("poll should pass");
        if snapshot.attachments.iter().any(|view| {
            view.attachment_id == attachment_id && view.state == AttachmentState::Available
        }) {
            return;
        }
        std::thread::sleep(std::time::Duration::from_millis(100));
    }
    panic!("attachment did not finish downloading");
}

fn wait_until_ready(alice: &mut PrivateDmRuntime, bob: &mut PrivateDmRuntime, session_id: &str) {
    // The Moss handshake is timing-sensitive; allow generous headroom so
    // the test stays green under full-suite CPU contention.
    for _ in 0..200 {
        let alice_ready = alice
            .poll_session(session_id)
            .expect("Alice poll should pass")
            .state
            == DmSessionState::Connected;
        let bob_ready = bob
            .poll_session(session_id)
            .expect("Bob poll should pass")
            .state
            == DmSessionState::Connected;
        if alice_ready && bob_ready {
            return;
        }
        std::thread::sleep(std::time::Duration::from_millis(100));
    }

    panic!("sessions did not become ready");
}

fn wait_for_pending_call(runtime: &mut PrivateDmRuntime, session_id: &str, call_id: &str) {
    for _ in 0..60 {
        let snapshot = runtime.poll_session(session_id).expect("poll should pass");
        if snapshot
            .pending_call
            .as_ref()
            .is_some_and(|call| call.call_id == call_id)
        {
            return;
        }
        std::thread::sleep(std::time::Duration::from_millis(100));
    }
    panic!("pending call did not arrive");
}

fn wait_for_active_call(
    alice: &mut PrivateDmRuntime,
    bob: &mut PrivateDmRuntime,
    session_id: &str,
    call_id: &str,
) {
    for _ in 0..60 {
        let alice_active = alice
            .poll_session(session_id)
            .expect("Alice poll should pass")
            .active_call
            .as_ref()
            .is_some_and(|call| call.call_id == call_id);
        let bob_active = bob
            .poll_session(session_id)
            .expect("Bob poll should pass")
            .active_call
            .as_ref()
            .is_some_and(|call| call.call_id == call_id);
        if alice_active && bob_active {
            return;
        }
        std::thread::sleep(std::time::Duration::from_millis(100));
    }
    panic!("call did not become active");
}

fn wait_for_call_frame(runtime: &PrivateDmRuntime, call_id: &str) -> Vec<u8> {
    for _ in 0..60 {
        let frames = runtime.call_media().drain(call_id);
        if let Some(frame) = frames.into_iter().next() {
            return frame;
        }
        std::thread::sleep(std::time::Duration::from_millis(100));
    }
    panic!("voice frame did not arrive");
}

fn test_call_frame(seq: u64, payload: &[u8]) -> Vec<u8> {
    let mut frame = seq.to_be_bytes().to_vec();
    frame.extend_from_slice(payload);
    frame
}

fn wait_for_message(
    runtime: &mut PrivateDmRuntime,
    session_id: &str,
    body: &str,
) -> SessionSnapshot {
    for _ in 0..30 {
        let snapshot = runtime.poll_session(session_id).expect("poll should pass");
        if snapshot.messages.iter().any(|message| message.body == body) {
            return snapshot;
        }
        std::thread::sleep(std::time::Duration::from_millis(100));
    }

    panic!("message did not arrive");
}

#[path = "runtime_tests/handshake.rs"]
mod handshake;

#[path = "runtime_tests/peer_discovery.rs"]
mod peer_discovery;

#[path = "runtime_tests/address_auth.rs"]
mod address_auth;

#[path = "runtime_tests/restore.rs"]
mod restore;

#[path = "runtime_tests/attachments.rs"]
mod attachments;

#[path = "runtime_tests/calls.rs"]
mod calls;
