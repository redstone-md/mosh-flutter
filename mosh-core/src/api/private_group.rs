//! Private-group facade.
//!
//! Surfaces the former `private_group_*` Tauri command group: create, join,
//! send, retry_message, poll, list, close, attachment send/download/cancel,
//! and the send/dismiss DM-offer commands. Poll maps to a
//! `StreamSink`-returning facade function, mirroring the former Tauri event
//! that streamed private-group updates.
//!
//! Stub: signatures laid for the slice-one boundary; bodies `todo!()` —
//! implemented in a later slice (S2: ADR 0016 OnceLock singleton for the
//! private-group runtime family, bound through the bridge). No `OnceLock` /
//! `ensure_runtime` here yet — these stubs compile only and carry no
//! runtime behavior, so the bridge can be generated against the full
//! private-group command surface before the wiring lands.
//!
//! TYPES (ADR 0010 — 1:1 mapping, DRY): request and return types are the
//! runtime's own, re-exported here via
//! `use crate::private_group_runtime::{...}`. They are NOT redefined.
//! `Result<T, String>` matches the Tauri command shape exactly; the future
//! implementation maps `PrivateGroupError` to a plain `String` so the bridge
//! surfaces it as a Dart exception.

// Stub api signatures mirror the future runtime contract (ADR 0010); params
// are intentionally unused until the runtime lands.
#![allow(unused_variables)]

use crate::private_dm_runtime::{AttachmentSendResult, VoiceMeta};
use crate::private_group_runtime::{
    CreateGroupRequest, GroupCreated, GroupLeaveResult, GroupListSnapshot, GroupSendResult,
    GroupSnapshot, JoinGroupRequest,
};

/// Create a private MLS group (1:1 port of `private_group_create`).
pub fn create_group(request: CreateGroupRequest) -> Result<GroupCreated, String> {
    todo!("slice-2: implement private_group_create")
}

/// Join a private group from an invite URI (1:1 port of `private_group_join`).
pub fn join_group(request: JoinGroupRequest) -> Result<GroupSnapshot, String> {
    todo!("slice-2: implement private_group_join")
}

/// Send a message into a private group (1:1 port of `private_group_send`).
pub fn send(group_id: String, body: String) -> Result<GroupSendResult, String> {
    todo!("slice-2: implement private_group_send")
}

/// Retry a failed private-group message (1:1 port of
/// `private_group_retry_message`).
pub fn retry_message(group_id: String, message_id: String) -> Result<GroupSendResult, String> {
    todo!("slice-2: implement private_group_retry_message")
}

/// Poll a private group for its current snapshot (1:1 port of
/// `private_group_poll`).
pub fn poll(group_id: String) -> Result<GroupSnapshot, String> {
    todo!("slice-2: implement private_group_poll")
}

/// List all private groups and their snapshots (1:1 port of
/// `private_group_list`).
pub fn list() -> Result<GroupListSnapshot, String> {
    todo!("slice-2: implement private_group_list")
}

/// Close and tear down a private group (1:1 port of `private_group_close`).
pub fn close(group_id: String) -> Result<GroupLeaveResult, String> {
    todo!("slice-2: implement private_group_close")
}

/// Send an attachment into a private group (1:1 port of
/// `private_group_send_attachment`).
pub fn send_attachment(
    group_id: String,
    file_name: String,
    mime: String,
    data_base64: String,
    thumbnail_base64: Option<String>,
    voice: Option<VoiceMeta>,
) -> Result<AttachmentSendResult, String> {
    todo!("slice-2: implement private_group_send_attachment")
}

/// Download a private-group attachment (1:1 port of
/// `private_group_download_attachment`).
pub fn download_attachment(group_id: String, attachment_id: String) -> Result<(), String> {
    todo!("slice-2: implement private_group_download_attachment")
}

/// Cancel a private-group attachment transfer (1:1 port of
/// `private_group_cancel_attachment`).
pub fn cancel_attachment(group_id: String, attachment_id: String) -> Result<(), String> {
    todo!("slice-2: implement private_group_cancel_attachment")
}

/// Publish a private-DM invitation to one group member (1:1 port of
/// `private_group_send_dm_offer`).
pub fn send_dm_offer(
    group_id: String,
    target_fingerprint: String,
    invite_uri: String,
) -> Result<(), String> {
    todo!("slice-2: implement private_group_send_dm_offer")
}

/// Dismiss a private-group DM offer (1:1 port of
/// `private_group_dismiss_dm_offer`).
pub fn dismiss_dm_offer(group_id: String, offer_id: String) -> Result<(), String> {
    todo!("slice-2: implement private_group_dismiss_dm_offer")
}
