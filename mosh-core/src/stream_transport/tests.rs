use super::*;
use std::cell::RefCell;

use crate::conversation::mesh::MeshInfo;
use crate::private_dm_runtime::transport::{PeerTransport, PublishError};

const BLOB: &str = "mls-blob/session-1";

fn envelope(participant: &str, index: u64) -> Vec<u8> {
    serde_json::to_vec(&serde_json::json!({
        "type": "Chunk",
        "participant_id": participant,
        "frame": {
            "attachment_id": "att-1",
            "chunk_index": index,
            "ciphertext_b64": "aGVsbG8",
        },
    }))
    .expect("envelope should serialize")
}

#[test]
fn frames_the_channel_around_the_envelope_and_deframes_back() {
    let payload = envelope("alice-participant", 7);

    let framed = frame(BLOB, &payload).expect("framing should succeed");
    let (channel, decoded) = deframe(&framed).expect("deframing should succeed");

    assert_eq!(channel, BLOB);
    assert_eq!(decoded, payload, "the envelope rides verbatim");
}

#[test]
fn deframe_rejects_what_the_room_wire_never_carries() {
    assert!(deframe(b"not a frame").is_none());
    assert!(deframe(b"{}").is_none());
    assert!(
        deframe(b"{\"channel\":\"mls-blob/x\"}").is_none(),
        "a frame without a payload field"
    );
    assert!(
        deframe(b"{\"payload_b64\":\"!!!!\"}").is_none(),
        "a frame with an invalid base64 payload"
    );
}

#[test]
fn stream_inbound_recognises_only_the_reserved_prefix() {
    let peer = "ab".repeat(32);
    assert!(is_stream_inbound(&stream_inbox_channel(&peer)));
    assert!(!is_stream_inbound(BLOB));
    assert!(!is_stream_inbound("mls-control/session-1"));
}

#[test]
fn passthrough_refiles_a_frame_under_its_blob_channel() {
    let peer = "ab".repeat(32);
    let payload = envelope("alice-participant", 3);
    let framed = frame(BLOB, &payload).expect("framing should succeed");

    let routed = passthrough_or_deframe(MossReceivedMessage {
        channel: stream_inbox_channel(&peer),
        payload: framed,
    });

    assert_eq!(routed.channel, BLOB);
    assert_eq!(routed.payload, payload);
}

#[test]
fn passthrough_is_identity_for_room_frames() {
    let message = MossReceivedMessage {
        channel: BLOB.to_string(),
        payload: b"room frame".to_vec(),
    };

    let routed = passthrough_or_deframe(message.clone());

    assert_eq!(routed.channel, message.channel);
    assert_eq!(routed.payload, message.payload);
}

#[test]
fn passthrough_keeps_an_undeframeable_stream_frame_unroutable() {
    let peer = "cd".repeat(32);
    let original = MossReceivedMessage {
        channel: stream_inbox_channel(&peer),
        payload: b"garbage".to_vec(),
    };

    let routed = passthrough_or_deframe(original.clone());

    // Unchanged: no runtime claims the reserved channel, so this frame
    // is dropped by the ordinary unclaimed-tail path, exactly once.
    assert_eq!(routed.channel, original.channel);
    assert_eq!(routed.payload, original.payload);
}

/// A transport whose stream door refuses everything, recording each
/// attempt; the room publish still works.
struct RefusingStreamTransport {
    attempts: std::sync::Mutex<Vec<String>>,
}

impl DmTransport for RefusingStreamTransport {
    fn open_room(
        &self,
        _room: &str,
        _channels: &[String],
        _listen_port: u16,
        _static_peer: Option<String>,
    ) -> Result<(), String> {
        Ok(())
    }

    fn close_room(&self, _room: &str, _channels: &[String], _label: &str) {}

    fn subscribe(&self, _room: &str, _channel: &str) -> Result<(), String> {
        Ok(())
    }

    fn unsubscribe(&self, _room: &str, _channel: &str) -> Result<(), String> {
        Ok(())
    }

    fn publish(&self, _room: &str, _channel: &str, _payload: &[u8]) -> Result<(), PublishError> {
        Err(PublishError::Other(
            "transport publish is not under test".to_string(),
        ))
    }

    fn connect_peer(&self, _peer_moss_id: &str) -> Result<(), String> {
        Ok(())
    }

    fn reach(&self, _peer_moss_id: &str) -> PeerTransport {
        PeerTransport::Direct
    }

    fn local_peer_id(&self) -> Option<String> {
        None
    }

    fn mesh_info(&self) -> Option<MeshInfo> {
        None
    }

    fn send_to_peer_stream(&self, peer_id: &str, payload: &[u8]) -> Result<(), String> {
        self.attempts
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .push(format!("{peer_id}:{}", payload.len()));
        Err(STREAM_REFUSAL.to_string())
    }

    fn drain(&self) -> Vec<MossReceivedMessage> {
        Vec::new()
    }

    fn drain_media(&self) -> Vec<MossReceivedMessage> {
        Vec::new()
    }
}

const STREAM_REFUSAL: &str = "stub stream refusal";

#[test]
fn send_chunk_falls_back_to_the_room_when_the_stream_refuses() {
    let payload = envelope("alice-participant", 0);
    let transport = RefusingStreamTransport {
        attempts: std::sync::Mutex::new(Vec::new()),
    };
    let room_log: RefCell<Vec<Vec<u8>>> = RefCell::new(Vec::new());
    let room = |bytes: &[u8]| -> Result<(), String> {
        room_log.borrow_mut().push(bytes.to_vec());
        Ok(())
    };

    let carrier = send_chunk(Some((&transport, "peer")), room, BLOB, &payload)
        .expect("the room fallback should carry the chunk");

    assert_eq!(
        carrier,
        Carrier::Room,
        "the caller learns the stream failed"
    );
    assert_eq!(
        transport
            .attempts
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .len(),
        1,
        "one stream try"
    );
    assert_eq!(
        *room_log.borrow(),
        vec![payload],
        "the room got the raw envelope, not the framed one"
    );
}

#[test]
fn send_chunk_falls_back_to_the_room_when_no_stream_peer_is_known() {
    let payload = envelope("alice-participant", 0);
    let room_log: RefCell<Vec<Vec<u8>>> = RefCell::new(Vec::new());
    let room = |bytes: &[u8]| -> Result<(), String> {
        room_log.borrow_mut().push(bytes.to_vec());
        Ok(())
    };

    send_chunk(None, room, BLOB, &payload).expect("the room should carry it");

    assert_eq!(*room_log.borrow(), vec![payload], "the room got the chunk");
}

#[test]
fn send_chunk_reports_the_room_refusal_when_both_paths_fail() {
    let payload = envelope("alice-participant", 2);
    let room = |_bytes: &[u8]| -> Result<(), String> { Err(ROOM_REFUSAL.to_string()) };

    let error = send_chunk(None, room, BLOB, &payload).expect_err("both paths refuse");

    assert!(
        error.contains(ROOM_REFUSAL),
        "the refusal rides out: {error}"
    );
}

const ROOM_REFUSAL: &str = "no peers reachable";

#[test]
fn reserved_prefix_never_collides_with_room_naming() {
    assert_ne!(
        STREAM_INBOX_CHANNEL_PREFIX, "mls-blob/",
        "the stream prefix must not be a room prefix"
    );
}
