//! Which wire a served chunk rides. The moss stream is a fast path only for a
//! peer moss holds a direct session with: for a relayed peer every send waits
//! on a relay round trip, and for a peer moss does not know `OpenStream` runs
//! a route lookup of up to 20 s — both while the runtime is locked. So those
//! peers go straight to the room wire, and a stream that failed is not tried
//! again for every chunk.

use super::state_tests::{accept, connect, invite, memory_pair, ALICE_ID, BOB_ID};
use super::*;
use crate::attachment_runtime::CHUNK_SIZE;
use crate::private_dm_runtime::transport::memory::MemoryNet;

const CHUNKS: usize = 3;

/// Alice sends a three-chunk file and Bob downloads it, polling both sides
/// until Bob holds it. Returns whether the download finished.
fn transfer(alice: &mut PrivateDmRuntime, bob: &mut PrivateDmRuntime, session_id: &str) -> bool {
    let bytes: Vec<u8> = (0..CHUNK_SIZE as usize * CHUNKS)
        .map(|index| (index % 251) as u8)
        .collect();
    let sent = alice
        .send_attachment(
            session_id,
            "file.bin".to_string(),
            "application/octet-stream".to_string(),
            bytes,
            None,
            None,
        )
        .expect("Alice should send the file");
    bob.poll_session(session_id).expect("poll should pass");
    bob.download_attachment(session_id, &sent.attachment_id)
        .expect("Bob should start the download");
    for _ in 0..50 {
        alice.poll_session(session_id).expect("poll should pass");
        let view = bob.poll_session(session_id).expect("poll should pass");
        let done = view.attachments.iter().any(|attachment| {
            attachment.attachment_id == sent.attachment_id
                && attachment.state == AttachmentState::Available
        });
        if done {
            return true;
        }
    }
    false
}

fn connected_pair(
    reach: PeerTransport,
) -> (Arc<MemoryNet>, PrivateDmRuntime, PrivateDmRuntime, String) {
    let (net, mut alice, mut bob) = memory_pair();
    net.link_both(ALICE_ID, BOB_ID, reach);
    let invite = invite(&mut alice);
    accept(&mut bob, &invite);
    connect(&mut alice, &mut bob, &invite.session_id);
    (net, alice, bob, invite.session_id)
}

#[test]
fn a_direct_peer_gets_its_chunks_over_the_stream() {
    let (net, mut alice, mut bob, session_id) = connected_pair(PeerTransport::Direct);
    assert!(transfer(&mut alice, &mut bob, &session_id));
    assert!(net.stream_attempts(ALICE_ID) >= CHUNKS);
}

#[test]
fn a_relayed_peer_gets_its_chunks_over_the_room_wire() {
    let (net, mut alice, mut bob, session_id) = connected_pair(PeerTransport::Relayed);
    assert!(transfer(&mut alice, &mut bob, &session_id));
    assert_eq!(
        net.stream_attempts(ALICE_ID),
        0,
        "a relayed stream send blocks on the relay; the room wire does not"
    );
}

#[test]
fn a_failed_stream_is_not_retried_for_every_chunk() {
    let (net, mut alice, mut bob, session_id) = connected_pair(PeerTransport::Direct);
    net.fail_streams(ALICE_ID, true);
    assert!(
        transfer(&mut alice, &mut bob, &session_id),
        "the room wire still carries the file"
    );
    assert_eq!(net.stream_attempts(ALICE_ID), 1);
}
