//! What the field log says about a DM session. A bug report is read from
//! these lines, so they must name real state changes and real causes: a line
//! written on every frame reads like a reconnect storm that never happened.

use super::state_tests::{accept, connect, invite, memory_pair, BOB_ID};
use super::*;
use crate::private_dm_runtime::transport::memory::MemoryNet;

/// How many field-log lines about `context` contain `needle`.
fn log_lines(context: &str, needle: &str) -> Vec<String> {
    let path = dlog::current_log_path().expect("the session wrote the log");
    std::fs::read_to_string(path)
        .expect("the log is readable")
        .lines()
        .filter(|line| line.contains(context) && line.contains(needle))
        .map(str::to_string)
        .collect()
}

#[test]
fn connected_is_logged_once_per_side_not_per_frame() {
    let (_net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    for body in ["one", "two", "three"] {
        bob.send_message(&invite.session_id, body.to_string())
            .expect("Bob should send");
        alice
            .poll_session(&invite.session_id)
            .expect("poll should pass");
        bob.poll_session(&invite.session_id)
            .expect("poll should pass");
    }

    assert_eq!(
        log_lines(&invite.session_id, "session connected").len(),
        2,
        "one change into Connected on each side"
    );
}

#[test]
fn an_unverifiable_hello_logs_why() {
    let (net, mut alice, mut bob) = memory_pair();
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);

    forge_hello_from_bob(&net, &invite);
    alice
        .poll_session(&invite.session_id)
        .expect("poll should pass");

    let lines = log_lines(&invite.session_id, "dropping unverifiable hello");
    assert_eq!(lines.len(), 1);
    assert!(
        lines[0].contains("dropping unverifiable hello: "),
        "the MLS error rides along: {}",
        lines[0]
    );
}

fn forge_hello_from_bob(net: &Arc<MemoryNet>, invite: &InviteCreated) {
    let forged = serde_json::to_vec(&ControlEnvelope::Hello {
        session_id: invite.session_id.clone(),
        participant_id: "peer-participant".to_string(),
        from_device: "Bob".to_string(),
        hello_ciphertext_b64: encode(b"not-an-mls-ciphertext"),
    })
    .expect("forged envelope should serialize");
    net.endpoint(BOB_ID)
        .publish(
            &invite.mesh_id,
            &control_channel(&invite.session_id),
            &forged,
        )
        .expect("a forged publish is still a publish");
}
