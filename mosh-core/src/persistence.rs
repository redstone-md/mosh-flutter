//! Encrypted redb persistence. Feature modules share one row and transaction boundary.
use crate::diagnostics_log::{self as dlog, kinds, LogLevel};
use flutter_rust_bridge::frb;
use redb::{Database, ReadableTable};

mod chat_names;
mod conversation_records;
mod crypto;
mod database;
mod dm_devices;
mod dm_history;
mod group_commits;
mod history;
mod mls_state;
mod org_acceptances;
#[cfg(test)]
mod org_acceptances_tests;
mod outbound;
mod records;
mod schema;
#[cfg(test)]
pub(crate) mod test_faults;
#[cfg(test)]
mod tests;

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
