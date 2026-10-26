//! Encrypted redb persistence. Feature modules share one row and transaction boundary.
use crate::diagnostics_log::{self as dlog, kinds, LogLevel};
use flutter_rust_bridge::frb;
use redb::{Database, ReadableTable};

mod attachment_gc;
mod attachment_refs;
pub(crate) mod background_calls;
pub(crate) mod background_delivery;
mod chat_names;
mod conversation_records;
mod crypto;
mod database;
mod deletion_acceptance;
mod deletion_guard;
mod deletion_index;
mod deletion_merge;
mod deletion_paging;
#[cfg(test)]
mod deletion_tests;
mod dm_devices;
mod dm_history;
pub(crate) mod history_admission;
pub(crate) use history_admission::HistoryAdmission;
mod group_commits;
mod group_names;
mod history;
mod history_erasure;
mod message_deletions;
mod mls_state;
mod org_acceptances;
#[cfg(test)]
mod org_acceptances_tests;
mod outbound;
mod outbound_guard;
mod plus;
mod records;
mod recovery;
pub(crate) use recovery::FrozenExport;
mod recovery_exports;
mod recovery_occurrences;
mod recovery_pages;
mod schema;
#[cfg(test)]
pub(crate) mod test_faults;
#[cfg(test)]
mod tests;

pub(crate) use background_delivery::BackgroundMessageAdmission;
pub use background_delivery::BackgroundNotification;
pub use crypto::{decrypt_blob, encrypt_blob};
use schema::*;
pub use schema::{HistoryTables, CHANNEL_HISTORY, DM_HISTORY, GROUP_HISTORY};

/// Persistence readiness reported by diagnostics.
#[derive(serde::Serialize, Clone)]
#[frb(non_opaque)]
pub struct PersistenceRuntimeStatus {
    pub backend: String,
    pub database: String,
    pub available: bool,
    pub encrypted_at_rest: bool,
    pub error: Option<String>,
}

#[derive(Debug)]
pub enum PersistenceError {
    Crypto(String),
    Io(String),
    Db(String),
    Json(String),
    Keychain(String),
}

impl std::fmt::Display for PersistenceError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Crypto(e) => write!(f, "persistence crypto error: {e}"),
            Self::Io(e) => write!(f, "persistence io error: {e}"),
            Self::Db(e) => write!(f, "persistence db error: {e}"),
            Self::Json(e) => write!(f, "persistence json error: {e}"),
            Self::Keychain(e) => write!(f, "persistence keychain error: {e}"),
        }
    }
}
impl std::error::Error for PersistenceError {}

pub struct Persistence {
    db: Database,
    dek: [u8; 32],
}

fn db_error(error: impl std::fmt::Display) -> PersistenceError {
    PersistenceError::Db(error.to_string())
}

#[cfg(test)]
mod history_admission_tests;

#[cfg(test)]
mod recovery_export_tests;
