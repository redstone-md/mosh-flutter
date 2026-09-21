//! The typing signal every live conversation kind shares.
//!
//! A composer re-asks on every keystroke; the runtime folds that down to
//! one steady refresh at `TYPING_REFRESH_MS`. The receiver owns the
//! deadline: a hint stays believable for `TYPING_EXPIRY_MS` and then
//! lapses, and a delivered message from the same hand clears it at once.
//! Nothing here keys on the kind — a DM has one counterpart slot, a group
//! a member roster — so the two kinds keep their own state and call the
//! shared gate and event helpers.

/// Minimum gap between TypingIndicator publishes from one side. Continued
/// input reads as one steady signal instead of a frame per key.
pub const TYPING_REFRESH_MS: u64 = 3_000;

/// How long a received hint stays believable without a refresh. The
/// receiver owns the expiry: a refresh inside the window renews it,
/// silence lets it lapse, and a real message clears it at once — a
/// delivered message contradicts "typing".
pub const TYPING_EXPIRY_MS: u64 = 5_000;

/// Event code the diagnostics panel renders as "typing" (pinned in
/// `conversation::mesh`). Synthesized into the ring whenever a decrypted
/// hint lands or lapses, so the panel shows typing activity like the
/// node's own reports.
pub const TYPING_EVENT_CODE: i32 = 10;

/// Files one typing event (pinned code 10) into the diagnostics event
/// ring, the same insert `on_moss_event` does for the node's own reports.
/// `room` is the kind's own id: a session id, a group id.
pub fn push_typing_event(room: &str, phase: &str) {
    let detail = serde_json::json!({
        "room": room,
        "phase": phase,
    });
    crate::moss_ffi::push_app_event(TYPING_EVENT_CODE, &detail.to_string());
}

/// The send cadence gate one side of a conversation owns. The caller still
/// builds, encrypts and routes the frame, because that part is the kind's.
#[derive(Default, Debug)]
pub struct TypingGate {
    last_send_ms: u64,
}

impl TypingGate {
    /// Whether a typing publish is due at `now`; when it is, `now` becomes
    /// the remembered send time.
    pub fn send_due(&mut self, now: u64) -> bool {
        if now.saturating_sub(self.last_send_ms) < TYPING_REFRESH_MS {
            return false;
        }
        self.last_send_ms = now;
        true
    }

    /// When a hint received at `now` stops being believable.
    pub fn deadline(now: u64) -> u64 {
        now.saturating_add(TYPING_EXPIRY_MS)
    }

    /// Moves the last-send stamp back, so the next `send_due` passes.
    /// Tests use this to cross the cadence without sleeping.
    #[cfg(test)]
    pub fn age_by(&mut self, ms: u64) {
        self.last_send_ms = self.last_send_ms.saturating_sub(ms);
    }
}
