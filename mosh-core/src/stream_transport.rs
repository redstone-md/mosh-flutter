//! The attachment chunk carrier: moss streams first, room wire as fallback.
//!
//! Spec issue #8 keeps the chunk protocol (requests, retry, dedup) byte for
//! byte and changes only what carries each `BlobEnvelope`. This module owns
//! that carrier:
//!
//! - **Send** — when a direct moss peer id is known and the loaded library
//!   carries the stream symbols, the framed envelope goes down
//!   [`ATTACHMENT_STREAM_ID`] (moss itself routes direct, or wraps it onto
//!   the relay with its 8-byte `MSs1` header). A stream failure of any kind
//!   (`RELAY_FAILED`, a missing symbol) falls back to the room publish, so a
//!   counterpart library without streams receives exactly as before.
//! - **Receive** — a frame arriving on the stream callback carries no room
//!   context (the callback only knows the sending peer id), so the payload is
//!   framed: a JSON header naming the destination channel wraps the original
//!   envelope bytes (base64, so the header stays one clean JSON object).
//!   [`ingest`] peels the frame open and re-files it into the process inbox
//!   under that real channel, where the runtimes' existing
//!   `drain` → `handle_blob` path takes over unchanged.
//! - **Rooms keep listening.** The receiver never drops its blob-channel
//!   subscription: the room wire is the fallback for both mixed versions and
//!   in-flight transfers across a carrier change, and dedup absorbs a chunk
//!   that arrives on both (the ingest path is idempotent per chunk index, and
//!   a repeated `Request` is re-served — that is the retry protocol).
//!
//! Scope: DM attachments only. Groups and channels have no single direct
//! peer — their blob traffic stays on the room wire this slice.
//!
//! Mixed-version framing: a peer that predates streams never receives a
//! stream send (the sender falls back on any stream error), so the framing is
//! only ever read by a peer running this same code — no old-client risk.
//!
//! ```mermaid
//! flowchart LR
//!     A["handle_blob serves chunk"] --> B{"stream peer known?"}
//!     B -- "yes" --> C["stream send"]
//!     B -- "no" --> D["room wire publish"]
//!     C -- "ok" --> E["delivered"]
//!     C -- "symbol / relay failure" --> D
//!     C --> F["stream callback (peer id, payload)"]
//!     F --> G["deframe: moss-stream/<peer>"]
//!     G --> H["ingest re-files under blob channel"]
//!     D --> H
//!     H --> I["handle_blob → transfer ingest"]
//! ```

use serde::{Deserialize, Serialize};

use crate::conversation::{decode, encode};
use crate::diagnostics_log::{self as dlog, kinds, LogLevel};
use crate::moss_ffi::MossReceivedMessage;
use crate::private_dm_runtime::transport::DmTransport;

/// Stream id 2: 0 (raw) and 1 (gossip) are reserved by the moss transport,
/// 100+ are the game preset, 200+ the TUN intranet. Attachment chunks are
/// the first messenger stream, so they take the lowest free id.
pub const ATTACHMENT_STREAM_ID: u32 = 2;

/// Prefix reserved for frames the stream callback files. Runtime inboxes
/// claim channels they recognise, so an unclaimed prefix lands in the
/// unclaimed tail — a stream frame for a conversation nobody owns must not
/// look like a room frame (or a control frame) to any claim.
pub const STREAM_INBOX_CHANNEL_PREFIX: &str = "moss-stream/";

/// The channel a stream-delivered frame is filed under before deframing:
/// the reserved prefix plus the sending peer's moss id, so [`ingest`] can
/// route without colliding with any room channel naming.
pub fn stream_inbox_channel(peer_id: &str) -> String {
    format!("{STREAM_INBOX_CHANNEL_PREFIX}{peer_id}")
}

/// Every channel a runtime should claim for stream-delivered frames: exactly
/// the reserved prefix. Registered alongside the room channels so a frame
/// that arrives before its owner is registered still has an owner.
pub fn is_stream_inbound(channel: &str) -> bool {
    channel.starts_with(STREAM_INBOX_CHANNEL_PREFIX)
}

/// The framing header: the destination channel is the one thing the stream
/// callback cannot carry, so it rides inside the frame. `payload_b64` is the
/// original BlobEnvelope JSON carried verbatim (the chunk protocol does not
/// change) — base64 keeps the header a clean single JSON object.
#[derive(Debug, Serialize, Deserialize)]
struct StreamFrame {
    /// The blob channel the runtime's `handle_blob` is parked on.
    channel: String,
    /// The original BlobEnvelope JSON, UTF-8-lossless base64.
    payload_b64: String,
}

/// Wrap an envelope for the stream path.
fn frame(channel: &str, payload: &[u8]) -> Option<Vec<u8>> {
    let payload_b64 = encode(payload);
    serde_json::to_vec(&StreamFrame {
        channel: channel.to_string(),
        payload_b64,
    })
    .ok()
}

/// Public framing for callers outside this module (the dm runtime tests
/// build a frame the way the stream callback would deliver it).
#[cfg(test)]
pub(crate) fn frame_for_channel(channel: &str, payload: &[u8]) -> Option<Vec<u8>> {
    frame(channel, payload)
}

/// Peel a stream-delivered frame back into (channel, envelope bytes).
/// `None` for anything that is not a frame this carrier produced.
fn deframe(payload: &[u8]) -> Option<(String, Vec<u8>)> {
    let frame: StreamFrame = serde_json::from_slice(payload).ok()?;
    let bytes = decode(&frame.payload_b64).ok()?;
    Some((frame.channel, bytes))
}

/// Carry one blob frame to a direct peer over a moss stream, with the room
/// wire as the declared fallback. `stream` carries the known direct peer;
/// its absence — a group or channel frame, or a DM whose counterpart id is
/// not known yet — goes straight to the room, which is the normal path for
/// every conversation kind but a connected DM. A stream failure falls back
/// to the room publish; only when the room refuses too does the caller see
/// an error.
pub fn send_chunk(
    stream: Option<(&dyn DmTransport, &str)>,
    room: impl FnOnce(&[u8]) -> Result<(), String>,
    blob_channel: &str,
    payload: &[u8],
) -> Result<(), String> {
    if let Some((transport, peer_id)) = stream {
        let framed = frame(blob_channel, payload)
            .ok_or_else(|| FRAMING_FAILED.to_string())
            .and_then(|framed| transport.send_to_peer_stream(peer_id, &framed));
        if framed.is_ok() {
            return Ok(());
        }
        // Any stream refusal — symbol missing, relay failed, node gone —
        // degrades to the room wire. The chunk protocol retries on top.
        dlog::write(
            LogLevel::Info,
            kinds::STREAM,
            blob_channel,
            STREAM_FALLBACK_NOTE,
        );
    }
    room(payload).map_err(|error| format!("{ROOM_REFUSED_NOTE}: {error}"))
}

const FRAMING_FAILED: &str = "stream carrier could not frame the envelope";
const STREAM_FALLBACK_NOTE: &str = "stream carrier fell back to the room wire";
const ROOM_REFUSED_NOTE: &str = "room wire refused the blob frame";

/// A stream frame arrived on the reserved inbox channel: peel the framing and
/// hand back the message the runtime routes — the re-filed envelope under its
/// real blob channel. A frame nobody can deframe is kept as-is with a note,
/// so the drop stays observable at the claim layer instead of silently
/// vanishing: no runtime recognises the reserved channel, so the frame is
/// still dropped exactly once. Room frames are identity.
pub fn passthrough_or_deframe(message: MossReceivedMessage) -> MossReceivedMessage {
    let Some(peer_id) = message.channel.strip_prefix(STREAM_INBOX_CHANNEL_PREFIX) else {
        return message;
    };
    let Some((channel, payload)) = deframe(&message.payload) else {
        dlog::write(
            LogLevel::Warn,
            kinds::STREAM,
            peer_id,
            "dropping a stream frame that does not deframe",
        );
        return message;
    };
    MossReceivedMessage { channel, payload }
}

#[cfg(test)]
mod tests {
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

        fn publish(
            &self,
            _room: &str,
            _channel: &str,
            _payload: &[u8],
        ) -> Result<(), PublishError> {
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

        send_chunk(Some((&transport, "peer")), room, BLOB, &payload)
            .expect("the room fallback should carry the chunk");

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
}
