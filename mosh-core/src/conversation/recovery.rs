//! Bounded history progress shared by conversation kinds.
use serde::{Deserialize, Serialize};
pub(crate) mod cursor;
pub(crate) mod fragment;
pub(crate) mod manifest;
pub(crate) mod occurrence;
pub(crate) mod wire;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HistorySyncState {
    WaitingForSource,
    Importing,
    Complete,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HistorySync {
    pub state: HistorySyncState,
    pub reason: Option<HistorySyncReason>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HistorySyncReason {
    SourceUnavailable,
    EvidenceMissing,
    Unsupported,
    StorageRefused,
}

impl Default for HistorySync {
    fn default() -> Self {
        Self {
            state: HistorySyncState::WaitingForSource,
            reason: Some(HistorySyncReason::SourceUnavailable),
        }
    }
}

/// Retained import provenance; a carrier signature never upgrades original authorship.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HistoryEvidence {
    pub holder_key: String,
    pub classification: HistoryClassification,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HistoryClassification {
    OriginalOrigin,
    LegacyUnsigned,
}
