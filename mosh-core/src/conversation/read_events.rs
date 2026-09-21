//! The read-receipt event every conversation kind files into the
//! diagnostics ring.
//!
//! One pinned event code, filed on BOTH sides of a receipt: when one lands
//! (the sender learns its message was read) and when the receiver sends
//! one (the receiver's own honest event log).

/// Event code the diagnostics panel renders as "message_read" (pinned in
/// `conversation::mesh`).
pub const READ_EVENT_CODE: i32 = 9;

/// Files one read event (pinned code 9) into the diagnostics event ring,
/// the same insert `on_moss_event` does for the node's own reports.
/// `room` is the kind's own id: a session id, a group id.
pub fn push_read_event(room: &str, message_id: &str, phase: &str) {
    let detail = serde_json::json!({
        "room": room,
        "message_id": message_id,
        "phase": phase,
    });
    crate::moss_ffi::push_app_event(READ_EVENT_CODE, &detail.to_string());
}
