//! The six shared conversation actions (ADR 0024).
//!
//! Send, retry, send/download/cancel attachment, and leave exist once here,
//! for every conversation kind: the kind rides in a typed
//! [`BridgeConversationRef`] instead of in the function name. Eighteen
//! per-kind bridge functions collapse onto these six. The bridge function is
//! the only place that decides which runtime lock it addresses — Dart hands
//! over the kind and never re-decides it.
//!
//! OWNERSHIP: the three `OnceLock` runtime owners stay independent (ADR 0016,
//! ADR 0019). Each dispatch arm borrows its kind's existing
//! `ensure_runtime()` lock; nothing here constructs or merges runtimes.
//!
//! ERRORS: failures surface as the typed `ConversationBridgeError` through
//! the `From` impls over the runtime error enums, so Dart can branch on what
//! to do about a failure. Each kind facade's `ensure_runtime()` already
//! answers `Unavailable` when the runtime cannot be driven, so a dispatch
//! arm is two `?`s and no mapping of its own.
//!
//! SUCCESS PAYLOADS ARE DROPPED. The old wrappers returned send/leave result
//! DTOs that no Dart caller read outside the generated bindings; delivery
//! and transfer state already reach Dart through the next snapshot poll
//! (ADR 0021, ADR 0022). Every function here answers success with `()`.
//!
//! This module is the only bridge path for the six actions: the per-kind
//! wrappers were migration scaffolding and are gone, and `decode_base64`
//! below is the one attachment decoder on the bridge.

use flutter_rust_bridge::frb;

use crate::api::conversation_bridge::{ConversationBridgeError, ConversationBridgeErrorKind};
use crate::attachment_runtime::VoiceMeta;

/// Which conversation kind a shared action addresses.
#[frb(non_opaque)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BridgeConversationKind {
    /// A private DM session (filed by session id).
    Dm,
    /// A public channel (filed by name).
    Channel,
    /// A private group (filed by group id).
    Group,
}

/// The conversation a shared action addresses: its kind and its id — a
/// session id, a channel name, or a group id, matching the kind. A raw
/// `kind:id` string never crosses the bridge; this struct is its replacement
/// (ADR 0024).
#[frb(non_opaque)]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BridgeConversationRef {
    pub kind: BridgeConversationKind,
    pub id: String,
}

/// One attachment send's payload: the encoded bytes plus the metadata the
/// receiver's snapshot needs. A struct rather than a parameter list because
/// the five travel together through every arm of the send.
#[frb(non_opaque)]
// No PartialEq: `VoiceMeta` (the voice clip's metadata) does not implement
// it, and no caller needs to compare payloads.
#[derive(Clone, Debug)]
pub struct BridgeAttachmentPayload {
    pub file_name: String,
    pub mime: String,
    pub data_base64: String,
    pub thumbnail_base64: Option<String>,
    pub voice: Option<VoiceMeta>,
}

/// Send a text message into the conversation.
pub fn send(reference: BridgeConversationRef, body: String) -> Result<(), ConversationBridgeError> {
    match reference.kind {
        BridgeConversationKind::Dm => {
            super::private_dm::ensure_runtime()?
                .as_mut()
                .expect("ensure_runtime guarantees Some")
                .send_message(&reference.id, body)
                .map(|_| ())?;
        }
        BridgeConversationKind::Channel => {
            super::channel::ensure_runtime()?
                .as_mut()
                .expect("ensure_runtime guarantees Some")
                .send(&reference.id, body)
                .map(|_| ())?;
        }
        BridgeConversationKind::Group => {
            super::private_group::ensure_runtime()?
                .as_mut()
                .expect("ensure_runtime guarantees Some")
                .send(&reference.id, body)
                .map(|_| ())?;
        }
    }
    Ok(())
}

/// Retry a failed outbound message by its message id.
pub fn retry(
    reference: BridgeConversationRef,
    message_id: String,
) -> Result<(), ConversationBridgeError> {
    match reference.kind {
        BridgeConversationKind::Dm => {
            super::private_dm::ensure_runtime()?
                .as_mut()
                .expect("ensure_runtime guarantees Some")
                .retry_message(&reference.id, &message_id)
                .map(|_| ())?;
        }
        BridgeConversationKind::Channel => {
            super::channel::ensure_runtime()?
                .as_mut()
                .expect("ensure_runtime guarantees Some")
                .retry_message(&reference.id, &message_id)
                .map(|_| ())?;
        }
        BridgeConversationKind::Group => {
            super::private_group::ensure_runtime()?
                .as_mut()
                .expect("ensure_runtime guarantees Some")
                .retry_message(&reference.id, &message_id)
                .map(|_| ())?;
        }
    }
    Ok(())
}

/// Send an attachment into the conversation. The bytes arrive base64-encoded
/// (the bridge contract every send_attachment facade keeps); a payload that
/// does not decode is `InvalidInput` before any runtime is touched. The new
/// attachment's id and hash are dropped — the next snapshot poll carries
/// them.
pub fn send_attachment(
    reference: BridgeConversationRef,
    payload: BridgeAttachmentPayload,
) -> Result<(), ConversationBridgeError> {
    match reference.kind {
        BridgeConversationKind::Dm => dm_send_attachment(&reference.id, payload)?,
        BridgeConversationKind::Channel => channel_send_attachment(&reference.id, payload)?,
        BridgeConversationKind::Group => group_send_attachment(&reference.id, payload)?,
    }
    Ok(())
}

/// The DM arm of `send_attachment`. Split out per kind because the runtime
/// call carries six arguments, which is where this function's dispatch stays
/// readable. Decode happens before the lock, as on the bridge function.
fn dm_send_attachment(
    id: &str,
    payload: BridgeAttachmentPayload,
) -> Result<(), ConversationBridgeError> {
    let bytes = decode_base64(&payload.data_base64)?;
    let BridgeAttachmentPayload {
        file_name,
        mime,
        thumbnail_base64,
        voice,
        ..
    } = payload;
    super::private_dm::ensure_runtime()?
        .as_mut()
        .expect("ensure_runtime guarantees Some")
        .send_attachment(id, file_name, mime, bytes, thumbnail_base64, voice)
        .map(|_| ())
        .map_err(ConversationBridgeError::from)
}

/// The channel arm of `send_attachment`. See `dm_send_attachment`.
fn channel_send_attachment(
    id: &str,
    payload: BridgeAttachmentPayload,
) -> Result<(), ConversationBridgeError> {
    let bytes = decode_base64(&payload.data_base64)?;
    let BridgeAttachmentPayload {
        file_name,
        mime,
        thumbnail_base64,
        voice,
        ..
    } = payload;
    super::channel::ensure_runtime()?
        .as_mut()
        .expect("ensure_runtime guarantees Some")
        .send_attachment(id, file_name, mime, bytes, thumbnail_base64, voice)
        .map(|_| ())
        .map_err(ConversationBridgeError::from)
}

/// The group arm of `send_attachment`. See `dm_send_attachment`.
fn group_send_attachment(
    id: &str,
    payload: BridgeAttachmentPayload,
) -> Result<(), ConversationBridgeError> {
    let bytes = decode_base64(&payload.data_base64)?;
    let BridgeAttachmentPayload {
        file_name,
        mime,
        thumbnail_base64,
        voice,
        ..
    } = payload;
    super::private_group::ensure_runtime()?
        .as_mut()
        .expect("ensure_runtime guarantees Some")
        .send_attachment(id, file_name, mime, bytes, thumbnail_base64, voice)
        .map(|_| ())
        .map_err(ConversationBridgeError::from)
}

/// Begin (or retry) downloading a peer's attachment; progress is reported in
/// the next snapshot poll.
pub fn download_attachment(
    reference: BridgeConversationRef,
    attachment_id: String,
) -> Result<(), ConversationBridgeError> {
    match reference.kind {
        BridgeConversationKind::Dm => {
            super::private_dm::ensure_runtime()?
                .as_mut()
                .expect("ensure_runtime guarantees Some")
                .download_attachment(&reference.id, &attachment_id)?;
        }
        BridgeConversationKind::Channel => {
            super::channel::ensure_runtime()?
                .as_mut()
                .expect("ensure_runtime guarantees Some")
                .download_attachment(&reference.id, &attachment_id)?;
        }
        BridgeConversationKind::Group => {
            super::private_group::ensure_runtime()?
                .as_mut()
                .expect("ensure_runtime guarantees Some")
                .download_attachment(&reference.id, &attachment_id)?;
        }
    }
    Ok(())
}

/// Cancel an in-flight attachment transfer.
pub fn cancel_attachment(
    reference: BridgeConversationRef,
    attachment_id: String,
) -> Result<(), ConversationBridgeError> {
    match reference.kind {
        BridgeConversationKind::Dm => {
            super::private_dm::ensure_runtime()?
                .as_mut()
                .expect("ensure_runtime guarantees Some")
                .cancel_attachment(&reference.id, &attachment_id)?;
        }
        BridgeConversationKind::Channel => {
            super::channel::ensure_runtime()?
                .as_mut()
                .expect("ensure_runtime guarantees Some")
                .cancel_attachment(&reference.id, &attachment_id)?;
        }
        BridgeConversationKind::Group => {
            super::private_group::ensure_runtime()?
                .as_mut()
                .expect("ensure_runtime guarantees Some")
                .cancel_attachment(&reference.id, &attachment_id)?;
        }
    }
    Ok(())
}

/// Leave the conversation and tear it down: `close_session` for a DM,
/// `leave` for a channel, `close` for a group — one action, three former
/// names.
pub fn leave(reference: BridgeConversationRef) -> Result<(), ConversationBridgeError> {
    match reference.kind {
        BridgeConversationKind::Dm => {
            super::private_dm::ensure_runtime()?
                .as_mut()
                .expect("ensure_runtime guarantees Some")
                .close_session(&reference.id)
                .map(|_| ())?;
        }
        BridgeConversationKind::Channel => {
            super::channel::ensure_runtime()?
                .as_mut()
                .expect("ensure_runtime guarantees Some")
                .leave(&reference.id)
                .map(|_| ())?;
        }
        BridgeConversationKind::Group => {
            super::private_group::ensure_runtime()?
                .as_mut()
                .expect("ensure_runtime guarantees Some")
                .close(&reference.id)
                .map(|_| ())?;
        }
    }
    Ok(())
}

/// Tell the conversation's counterpart the user is typing. DMs and groups
/// carry the hint over their MLS-encrypted control wire; a channel has no
/// counterpart to tell, so its arm is a silent no-op (the UI never calls
/// it for a channel anyway — the arm exists so the kind dispatch stays
/// total). Fire-and-forget semantics: the runtime throttles repeats on its
/// own cadence and the hint reaches the other side with the next poll of
/// ITS snapshot, so success is `()`.
pub fn typing_signal(
    reference: BridgeConversationRef,
) -> Result<(), ConversationBridgeError> {
    match reference.kind {
        BridgeConversationKind::Dm => {
            super::private_dm::ensure_runtime()?
                .as_mut()
                .expect("ensure_runtime guarantees Some")
                .typing_signal(&reference.id)?;
        }
        BridgeConversationKind::Group => {
            super::private_group::ensure_runtime()?
                .as_mut()
                .expect("ensure_runtime guarantees Some")
                .typing_signal(&reference.id)?;
        }
        BridgeConversationKind::Channel => {}
    }
    Ok(())
}

/// Auto-trigger the read receipts when the conversation is open: receipts
/// every counterpart message the local user has not yet receipted. The
/// receipts themselves ride the DM control wire; a group and a channel
/// have no read receipts in this slice, so those arms are silent no-ops.
/// The sender's own ticks re-color on the OTHER side with its next poll.
pub fn mark_viewed(
    reference: BridgeConversationRef,
) -> Result<(), ConversationBridgeError> {
    match reference.kind {
        BridgeConversationKind::Dm => {
            super::private_dm::ensure_runtime()?
                .as_mut()
                .expect("ensure_runtime guarantees Some")
                .mark_viewed(&reference.id)?;
        }
        BridgeConversationKind::Group | BridgeConversationKind::Channel => {}
    }
    Ok(())
}

/// Decode the bridge's base64 attachment payload. A payload that does not
/// decode is the caller's mistake, so it is `InvalidInput`, raised before
/// any runtime lock is taken.
fn decode_base64(value: &str) -> Result<Vec<u8>, ConversationBridgeError> {
    use base64::Engine;
    base64::engine::general_purpose::STANDARD
        .decode(value)
        .map_err(|error| {
            ConversationBridgeError::new(
                ConversationBridgeErrorKind::InvalidInput,
                format!("attachment payload is not valid base64: {error}"),
            )
        })
}

#[cfg(test)]
mod tests;
