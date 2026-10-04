//! Moss stream carrier with room-publish fallback. Stream frames name the
//! destination channel; ingest routes them into the existing runtime inbox.
//! DMs use stream 2 for attachments, admission and live text. Groups/channels
//! use room traffic. Keep blob subscriptions active for fallback and dedup.

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

/// Which wire carried a blob frame.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Carrier {
    Stream,
    Room,
}

/// Carry one blob frame to a direct peer over a moss stream, with the room
/// wire as the declared fallback. `stream` carries the known direct peer;
/// its absence — a group or channel frame, or a DM whose counterpart is not
/// directly connected — goes straight to the room, which is the normal path
/// for every conversation kind but a connected DM. A stream failure falls
/// back to the room publish; only when the room refuses too does the caller
/// see an error. The answer names the wire that took the frame, so a caller
/// that offered a stream can tell the stream just failed.
pub fn send_chunk(
    stream: Option<(&dyn DmTransport, &str)>,
    room: impl FnOnce(&[u8]) -> Result<(), String>,
    blob_channel: &str,
    payload: &[u8],
) -> Result<Carrier, String> {
    if let Some((transport, peer_id)) = stream {
        let framed = frame(blob_channel, payload)
            .ok_or_else(|| FRAMING_FAILED.to_string())
            .and_then(|framed| transport.send_to_peer_stream(peer_id, &framed));
        if framed.is_ok() {
            return Ok(Carrier::Stream);
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
    room(payload)
        .map(|()| Carrier::Room)
        .map_err(|error| format!("{ROOM_REFUSED_NOTE}: {error}"))
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
mod tests;
