//! Code shared by every kind of conversation.
//!
//! A DM, an org group and a public channel differ in how they encrypt and
//! where they publish. Everything under this module is the part that does not
//! differ: the attachment slot table, the message log, the seen-key ring, the
//! mesh view a snapshot ends with, the path a message takes on its way out,
//! the DM invitations one member offers another.
//! Each runtime holds these as fields, or calls them, instead of keeping its
//! own copy, so a fix proven in one kind holds for all three. What each kind
//! keeps on disk goes through one store too, with the table names as data,
//! and an attachment's bytes go in and out through one transfer.

pub mod attachments;
pub mod dedup;
pub mod dm_offers;
pub mod history;
pub mod mesh;
pub mod message_log;
pub mod outbound;
pub mod read_events;
pub mod runtime;
#[cfg(test)]
pub mod test_message;
pub mod transfer;
pub mod typing;

use message_log::LogError;

/// Wall-clock milliseconds. Zero if the system clock is set before the epoch,
/// which only a badly set machine reports.
pub fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// Base64 for the payload bytes a stored record carries. Every kind writes
/// its outbound payloads and its attachment blobs this way.
pub fn encode(bytes: &[u8]) -> String {
    base64::Engine::encode(&base64::engine::general_purpose::STANDARD, bytes)
}

pub fn decode(encoded: &str) -> Result<Vec<u8>, LogError> {
    base64::Engine::decode(&base64::engine::general_purpose::STANDARD, encoded)
        .map_err(|error| LogError::Codec(error.to_string()))
}
