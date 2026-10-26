//! Bounded history progress shared by conversation kinds.
use serde::{Deserialize, Serialize};
pub(crate) mod coordinator;
pub(crate) mod cursor;
pub(crate) mod fragment;
pub(crate) mod manifest;
pub(crate) mod occurrence;
pub(crate) mod slots;
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub group: Option<GroupHistoryReferences>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HistoryClassification {
    OriginalOrigin,
    LegacyUnsigned,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupHistoryReferences {
    pub original_sender_proof_hash: String,
    pub content_proof_hash: Option<String>,
    pub acceptance_evidence_hash: String,
    pub first_evidence_hash: Option<String>,
    pub predecessor_hash: Option<String>,
    pub basis: GroupAcceptanceBasis,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GroupAcceptanceBasis {
    LiveAuthenticated,
    LocalPublication,
    InheritedImport,
    Legacy,
}
