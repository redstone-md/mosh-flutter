//! Code shared by every kind of conversation.
//!
//! A DM, an org group and a public channel differ in how they encrypt and
//! where they publish. Everything under this module is the part that does not
//! differ: the attachment slot table, the message log, the seen-key ring.
//! Each runtime holds these as fields instead of keeping its own copy, so a
//! fix proven in one kind holds for all three.

pub mod attachments;
pub mod dedup;
pub mod message_log;

/// Wall-clock milliseconds. Zero if the system clock is set before the epoch,
/// which only a badly set machine reports.
pub fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}
