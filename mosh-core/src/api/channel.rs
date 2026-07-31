//! Channel facade.
//!
//! Surfaces the former `channel_*` Tauri command group: join, leave, send,
//! retry_message, poll, list, attachment send/download/cancel, and the
//! send/dismiss DM-offer commands. Poll maps to a `StreamSink`-returning
//! facade function, mirroring the former Tauri event that streamed channel
//! updates.
//!
//! Stub: signatures laid for the slice-one boundary; bodies `todo!()` —
//! implemented in a later slice (S2: ADR 0016 OnceLock singleton for the
//! channel runtime family, bound through the bridge). No `OnceLock` /
//! `ensure_runtime` here yet — these stubs compile only and carry no
//! runtime behavior, so the bridge can be generated against the full
//! channel command surface before the wiring lands.
//!
//! TYPES (ADR 0010 — 1:1 mapping, DRY): request and return types are the
//! runtime's own, re-exported here via `use crate::channel_runtime::{...}`.
//! They are NOT redefined. `Result<T, String>` matches the Tauri command
//! shape exactly; the future implementation maps `ChannelRuntimeError` to a
//! plain `String` so the bridge surfaces it as a Dart exception.

use crate::channel_runtime::{
    ChannelLeaveResult, ChannelListSnapshot, ChannelSendResult, ChannelSnapshot, JoinChannelRequest,
};
use crate::private_dm_runtime::{AttachmentSendResult, VoiceMeta};

/// Join a public channel (1:1 port of the `channel_join` Tauri command).
pub fn join(request: JoinChannelRequest) -> Result<ChannelSnapshot, String> {
    todo!("slice-2: implement channel_join")
}

/// Leave a channel (1:1 port of `channel_leave`).
pub fn leave(name: String) -> Result<ChannelLeaveResult, String> {
    todo!("slice-2: implement channel_leave")
}

/// Send a message into a channel (1:1 port of `channel_send`).
pub fn send(name: String, body: String) -> Result<ChannelSendResult, String> {
    todo!("slice-2: implement channel_send")
}

/// Retry a failed channel message (1:1 port of `channel_retry_message`).
pub fn retry_message(name: String, message_id: String) -> Result<ChannelSendResult, String> {
    todo!("slice-2: implement channel_retry_message")
}

/// Poll a channel for its current snapshot (1:1 port of `channel_poll`).
/// The React frontend polled on a cadence; the bridge slice will offer the
/// `StreamSink`-returning variant alongside this one-shot poll.
pub fn poll(name: String) -> Result<ChannelSnapshot, String> {
    todo!("slice-2: implement channel_poll")
}

/// List all joined channels and their snapshots (1:1 port of `channel_list`).
pub fn list() -> Result<ChannelListSnapshot, String> {
    todo!("slice-2: implement channel_list")
}

/// Send an attachment into a channel (1:1 port of `channel_send_attachment`).
pub fn send_attachment(
    name: String,
    file_name: String,
    mime: String,
    data_base64: String,
    thumbnail_base64: Option<String>,
    voice: Option<VoiceMeta>,
) -> Result<AttachmentSendResult, String> {
    todo!("slice-2: implement channel_send_attachment")
}

/// Download a channel attachment (1:1 port of `channel_download_attachment`).
pub fn download_attachment(name: String, attachment_id: String) -> Result<(), String> {
    todo!("slice-2: implement channel_download_attachment")
}

/// Cancel a channel attachment transfer (1:1 port of `channel_cancel_attachment`).
pub fn cancel_attachment(name: String, attachment_id: String) -> Result<(), String> {
    todo!("slice-2: implement channel_cancel_attachment")
}

/// Publish a private-DM invitation to one channel member
/// (1:1 port of `channel_send_dm_offer`).
pub fn send_dm_offer(
    name: String,
    target_fingerprint: String,
    invite_uri: String,
) -> Result<(), String> {
    todo!("slice-2: implement channel_send_dm_offer")
}

/// Dismiss a channel DM offer (1:1 port of `channel_dismiss_dm_offer`).
pub fn dismiss_dm_offer(name: String, offer_id: String) -> Result<(), String> {
    todo!("slice-2: implement channel_dismiss_dm_offer")
}
