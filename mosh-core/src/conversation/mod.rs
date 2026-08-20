//! Code shared by every kind of conversation.
//!
//! A DM, an org group and a public channel differ in how they encrypt and
//! where they publish. Everything under this module is the part that does not
//! differ: the attachment slot table, the message log, the seen-key ring.
//! Each runtime holds these as fields instead of keeping its own copy, so a
//! fix proven in one kind holds for all three.

pub mod attachments;
pub mod message_log;
